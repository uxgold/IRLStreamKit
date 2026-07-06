// Production StreamEngine implementation. Owns the vendored Media instance,
// the MediaDelegateAdapter, the camera controller, and the tick loops. No
// singletons — the consuming app holds one instance in an app-lifetime
// service.

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class IRLStreamEngine: StreamEngine {
    public private(set) var state = StreamEngineState()

    @ObservationIgnored private var media: Media!
    @ObservationIgnored private let broadcaster = EventBroadcaster()
    @ObservationIgnored private let cameraController = CameraController()
    @ObservationIgnored private let ticker = EngineTicker()
    @ObservationIgnored private var signalTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var activeConfiguration: StreamConfiguration?
    @ObservationIgnored private var currentDevice: AVCaptureDevice?
    @ObservationIgnored let internalPreviewView: PreviewView

    public init() {
        internalPreviewView = PreviewView(frame: .zero)
        internalPreviewView.videoGravity = .resizeAspectFill
        let (stream, continuation) = AsyncStream.makeStream(of: EngineSignal.self)
        // Media retains its delegate strongly; the adapter must not retain the
        // engine (it only holds the stream continuation).
        media = Media(delegate: MediaDelegateAdapter(signals: continuation))
        signalTask = Task { [weak self] in
            for await signal in stream {
                guard let self else {
                    return
                }
                self.handle(signal)
            }
        }
        ticker.onAbrTick = { [weak self] in self?.abrTick() }
        ticker.onAudioTick = { [weak self] in self?.audioTick() }
        ticker.onStatsTick = { [weak self] in self?.statsTick() }
    }

    deinit {
        signalTask?.cancel()
        reconnectTask?.cancel()
    }

    // MARK: - StreamEngine

    public func events() -> AsyncStream<StreamEvent> {
        broadcaster.subscribe()
    }

    public func startSession(camera: CameraSelection) async throws(StreamEngineError) {
        guard case .idle = state.phase else {
            return // idempotent
        }
        if let permissionError = await CameraController.requestPermissions() {
            throw permissionError
        }
        guard let device = cameraController.device(for: camera) else {
            throw StreamEngineError.cameraUnavailable
        }
        currentDevice = device
        configureNetStream(endpoint: nil, video: VideoConfiguration())
        media.attachCamera(params: cameraController.attachParams(device: device))
        apply(.cameraChanged(camera))
        apply(.phaseChanged(.previewing))
    }

    public func stopSession() {
        guard case .previewing = state.phase else {
            return // no-op while idle or live
        }
        media.attachCamera(params: cameraController.detachParams())
        media.stopAllNetStreams()
        currentDevice = nil
        apply(.phaseChanged(.idle))
    }

    public func goLive(_ configuration: StreamConfiguration) async throws(StreamEngineError) {
        switch state.phase {
        case .previewing:
            break
        case .idle:
            throw StreamEngineError.notInSession
        case .connecting, .live, .reconnecting:
            throw StreamEngineError.alreadyLive
        }
        if let configurationError = ConfigurationValidator.validate(configuration) {
            throw StreamEngineError.invalidConfiguration(configurationError)
        }
        guard let device = currentDevice else {
            throw StreamEngineError.cameraUnavailable
        }
        activeConfiguration = configuration
        // setNetStream rebuilds the capture graph (fresh Processor), so the
        // encoder settings and camera attach must be re-applied after it.
        configureNetStream(endpoint: configuration.endpoint, video: configuration.video)
        applyEncoderSettings(configuration)
        media.attachCamera(params: cameraController.attachParams(device: device))
        startNetworkStream(configuration)
        var stats = StreamStatistics()
        stats.targetBitrate = configuration.video.targetBitrate
        stats.currentBitrate = configuration.video.targetBitrate
        apply(.statsUpdated(stats))
        apply(.phaseChanged(.connecting))
        ticker.start()
    }

    public func endStream() {
        guard state.phase.isLive || state.phase == .connecting else {
            return
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        ticker.stop()
        stopNetworkStream()
        activeConfiguration = nil
        apply(.phaseChanged(.previewing))
    }

    public func setCamera(_ camera: CameraSelection) {
        guard camera != state.camera else {
            return
        }
        guard let device = cameraController.device(for: camera) else {
            apply(.failed(.cameraUnavailable))
            return
        }
        currentDevice = device
        media.attachCamera(params: cameraController.attachParams(device: device))
        apply(.cameraChanged(camera))
    }

    public func setMicMuted(_ muted: Bool) {
        // State is confirmed via mediaOnAudioMuteChange, not set optimistically.
        media.setMute(on: muted)
    }

    public func setTargetBitrate(_ bitsPerSecond: Int) {
        media.setVideoStreamBitrate(bitrate: UInt32(max(0, bitsPerSecond)))
        var stats = state.stats
        stats.targetBitrate = bitsPerSecond
        apply(.statsUpdated(stats))
    }

    // MARK: - Signal handling (single consumer preserves callback ordering)

    private func handle(_ signal: EngineSignal) {
        switch signal {
        case .connected:
            switch state.phase {
            case .connecting, .reconnecting:
                apply(.phaseChanged(.live(since: Date())))
            case .idle, .previewing, .live:
                break
            }
        case let .disconnected(reason):
            handleDisconnect(reason: reason)
        case .audioMuteChanged:
            apply(.micMuteChanged(isMuted: media.getAudioLevel().isNaN))
        case .attachCameraError:
            apply(.cameraAttachFailed)
        case let .captureSessionError(message):
            apply(.failed(.captureSessionFailed(message)))
        case let .encoderResolutionChanged(size):
            apply(.encoderResolutionChanged(width: Int(size.width), height: Int(size.height)))
        case let .fps(fps):
            var stats = state.stats
            stats.encoderFps = fps
            apply(.statsUpdated(stats))
        case let .mediaError(message):
            apply(.failed(.connectionFailed(message)))
        }
    }

    private func handleDisconnect(reason: String) {
        guard state.phase.isLive || state.phase == .connecting else {
            return
        }
        guard let configuration = activeConfiguration else {
            apply(.phaseChanged(.previewing))
            return
        }
        apply(.phaseChanged(.reconnecting(reason: reason)))
        apply(.failed(.connectionFailed(reason)))
        let delay = reconnectDelaySeconds(configuration)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, case .reconnecting = self.state.phase else {
                return
            }
            self.stopNetworkStream()
            self.startNetworkStream(configuration)
        }
    }

    private func reconnectDelaySeconds(_ configuration: StreamConfiguration) -> Double {
        switch configuration.endpoint {
        case let .srtla(_, options), let .srt(_, options):
            options.reconnectDelaySeconds
        case .rtmp:
            5
        }
    }

    // MARK: - Media orchestration

    private func configureNetStream(endpoint: StreamEndpoint?, video: VideoConfiguration) {
        media.setNetStream(
            proto: Mapping.netStreamProtocol(endpoint),
            portrait: video.isPortrait,
            timecodesEnabled: false, // upstream: timecodes require NTP, off by default
            builtinAudioDelay: 0, // upstream: debug default
            destinations: [], // multi-destination RTMP is phase 2
            srtImplementation: .moblin, // upstream default implementation
            limitAdaptiveBitrateByTransportBitrate: true // upstream: rateControl != .cbr
        )
        // setNetStream created a fresh Processor: rebind the preview drawable
        // and start it (mirrors ModelStream.attachStream).
        if let processor = media.getProcessor() {
            let previewView = internalPreviewView
            processorControlQueue.async {
                processor.setDrawable(drawable: previewView)
                processor.startRunning()
            }
        }
        media.setScreenPreview(enabled: true)
    }

    private func applyEncoderSettings(_ configuration: StreamConfiguration) {
        let video = configuration.video
        media.setVideoSize(
            capture: Mapping.captureSize(video.resolution),
            canvas: video.isPortrait
                ? CGSize(width: video.resolution.dimensions.height, height: video.resolution.dimensions.width)
                : video.resolution.dimensions,
            stream: Mapping.streamDimensions(video)
        )
        media.setFps(fps: video.frameRate, preferAutoFps: false)
        media.setVideoProfile(profile: Mapping.videoProfile(video.codec))
        media.setAllowFrameReordering(value: false) // upstream: bFrames off by default
        media.setStreamKeyFrameInterval(seconds: 2) // upstream: maxKeyFrameInterval default
        media.setVideoStreamBitrate(bitrate: UInt32(video.targetBitrate))
        media.setAudioStreamBitrate(bitrate: configuration.audio.bitrate)
        media.setAudioStreamFormat(format: .aac)
    }

    private func startNetworkStream(_ configuration: StreamConfiguration) {
        switch configuration.endpoint {
        case let .srtla(url, options), let .srt(url, options):
            let isSrtla = if case .srtla = configuration.endpoint { true } else { false }
            if let settings = Mapping.adaptiveBitrateSettings(options.adaptiveBitrate) {
                media.setAdaptiveBitrateSettings(settings: settings)
            }
            media.srtStartStream(
                isSrtla: isSrtla,
                url: url.absoluteString,
                reconnectTime: options.reconnectDelaySeconds,
                targetBitrate: UInt32(configuration.video.targetBitrate),
                adaptiveBitrateAlgorithm: Mapping.toSettings(options.adaptiveBitrate),
                latency: Int32(options.latencyMilliseconds),
                experimental: false, // upstream: debug flag
                overheadBandwidth: 25, // upstream: SettingsStreamSrt default
                maximumBandwidthFollowInput: true, // upstream: SettingsStreamSrt default
                mpegtsPacketsPerPacket: 7, // upstream: SettingsStreamSrt default
                packetPadding: false, // upstream: debug flag
                networkInterfaceNames: [], // custom interface names are phase 2
                connectionPriorities: Mapping.toSettings(options.bondingPriorities),
                dnsLookupStrategy: .system // upstream: SettingsStreamSrt default
            )
        case let .rtmp(url):
            media.rtmpStartStream(
                url: url.absoluteString,
                targetBitrate: UInt32(configuration.video.targetBitrate),
                adaptiveBitrate: false // RTMP ABR is upstream-experimental; phase 2
            )
        }
    }

    private func stopNetworkStream() {
        switch activeConfiguration?.endpoint {
        case .srtla, .srt:
            media.srtStopStream()
        case .rtmp:
            media.rtmpStopStream()
        case nil:
            break
        }
    }

    // MARK: - Ticks

    private func abrTick() {
        _ = media.updateAdaptiveBitrate(overlay: false, relaxed: false)
    }

    private func audioTick() {
        let level = media.getAudioLevel()
        let audioLevel = AudioLevel(
            decibels: level.isNaN ? nil : level,
            channels: media.getNumberOfAudioChannels()
        )
        if audioLevel != state.audioLevel {
            apply(.audioLevelUpdated(audioLevel))
        }
    }

    private func statsTick() {
        media.updateSrtTransportBitrate()
        var stats = state.stats
        stats.transportBitrate = Int(media.streamTransportBitrate() ?? 0)
        stats.totalBytesSent = media.streamTotal()
        stats.currentBitrate = Int(media.getVideoStreamBitrate(bitrate: UInt32(max(0, stats.targetBitrate))))
        if stats != state.stats {
            apply(.statsUpdated(stats))
        }
        if let connections = media.srtlaConnectionStatistics() {
            let links = Mapping.bondingLinks(connections)
            if links != state.bondingLinks {
                apply(.bondingUpdated(links))
            }
        }
    }

    // MARK: - State funnel

    private func apply(_ event: StreamEvent) {
        state = StreamEventReducer.reduce(state, event)
        broadcaster.yield(event)
    }
}
