// Production StreamEngine implementation. Owns the vendored Media instance,
// the MediaDelegateAdapter, the camera controller, and the tick loops. No
// singletons — the consuming app holds one instance in an app-lifetime
// service.

import AVFoundation
import Foundation
import IRLTPBonding
import Observation

@MainActor
@Observable
public final class IRLStreamEngine: StreamEngine {
    public private(set) var state = StreamEngineState()

    @ObservationIgnored private var media: Media!
    @ObservationIgnored private let adapter: MediaDelegateAdapter
    @ObservationIgnored private let broadcaster = EventBroadcaster()
    @ObservationIgnored private let cameraController = CameraController()
    @ObservationIgnored private let ticker = EngineTicker()
    @ObservationIgnored private var signalTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var activeConfiguration: StreamConfiguration?
    @ObservationIgnored private var currentDevice: AVCaptureDevice?
    @ObservationIgnored private var streamGeneration = 0
    @ObservationIgnored private var isStartingSession = false
    // The user's intended mute. Media loses mute state whenever setNetStream
    // rebuilds the Processor (AudioUnit.muted defaults to false), so the
    // facade re-applies it after every rebuild — mirrors Moblin's
    // ModelStream.setNetStream -> updateMute(). Prevents a hot mic on go-live.
    @ObservationIgnored private var desiredMicMuted = false
    // streamTotal() resets on every (re)connect; accumulate across reconnects.
    @ObservationIgnored private var totalBytesBase: Int64 = 0
    @ObservationIgnored let internalPreviewView: PreviewView

    public init() {
        internalPreviewView = PreviewView(frame: .zero)
        internalPreviewView.videoGravity = .resizeAspectFill
        let (stream, continuation) = AsyncStream.makeStream(of: StampedSignal.self)
        // Media retains its delegate strongly; the adapter must not retain the
        // engine (it only holds the stream continuation).
        adapter = MediaDelegateAdapter(signals: continuation)
        media = Media(delegate: adapter)
        signalTask = Task { [weak self] in
            for await stamped in stream {
                guard let self else {
                    return
                }
                self.handle(stamped)
            }
        }
        ticker.onAbrTick = { [weak self] in self?.abrTick() }
        ticker.onAudioTick = { [weak self] in self?.audioTick() }
        ticker.onStatsTick = { [weak self] in self?.statsTick() }
    }

    deinit {
        signalTask?.cancel()
        reconnectTask?.cancel()
        // Media <-> Processor retain each other strongly; without this the
        // capture session (and a live stream) would keep running with no
        // remaining handle after the engine is deallocated.
        let media: Media = media
        let ticker = ticker
        let broadcaster = broadcaster
        Task { @MainActor in
            ticker.stop()
            media.getProcessor()?.stop()
            media.stopAllNetStreams()
            broadcaster.finish()
        }
    }

    // MARK: - StreamEngine

    public func events() -> AsyncStream<StreamEvent> {
        broadcaster.subscribe()
    }

    public func startSession(camera: CameraSelection) async throws(StreamEngineError) {
        guard case .idle = state.phase, !isStartingSession else {
            // Idempotent — but honor a camera switch while previewing.
            if case .previewing = state.phase, camera != state.camera {
                setCamera(camera)
            }
            return
        }
        isStartingSession = true
        defer { isStartingSession = false }
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
        switch state.phase {
        case .connecting:
            endStream() // tear the pending connection down first
        case .previewing:
            break
        case .idle, .live, .reconnecting:
            return
        }
        streamGeneration = adapter.bumpGeneration()
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
        streamGeneration = adapter.bumpGeneration()
        totalBytesBase = 0
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
        streamGeneration = adapter.bumpGeneration()
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
        desiredMicMuted = muted
        // State is confirmed via mediaOnAudioMuteChange, not set optimistically.
        media.setMute(on: muted)
    }

    public func setTargetBitrate(_ bitsPerSecond: Int) {
        media.setVideoStreamBitrate(bitrate: UInt32(clamping: max(0, bitsPerSecond)))
        var stats = state.stats
        stats.targetBitrate = bitsPerSecond
        apply(.statsUpdated(stats))
    }

    // MARK: - Signal handling (single consumer preserves callback ordering)

    private func handle(_ stamped: StampedSignal) {
        // Connection signals from an earlier stream generation belong to a
        // stream that was already stopped; applying them would corrupt the
        // phase machine of the current one.
        switch stamped.signal {
        case .connected, .disconnected, .mediaError:
            guard stamped.generation == streamGeneration else {
                return
            }
        case .audioMuteChanged, .attachCameraError, .captureSessionError,
             .encoderResolutionChanged, .fps:
            break
        }
        switch stamped.signal {
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
            self.totalBytesBase += self.media.streamTotal()
            self.stopNetworkStream()
            self.streamGeneration = self.adapter.bumpGeneration()
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
        // The fresh Processor lost the mute flag (AudioUnit.muted defaults to
        // false) — re-apply the user's intent, mirroring Moblin's updateMute().
        media.setMute(on: desiredMicMuted)
        // Rebind the preview drawable and start the new Processor (mirrors
        // ModelStream.attachStream).
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
        media.setVideoStreamBitrate(bitrate: UInt32(clamping: video.targetBitrate))
        media.setAudioStreamBitrate(bitrate: configuration.audio.bitrate)
        media.setAudioStreamFormat(format: .aac)
    }

    private func startNetworkStream(_ configuration: StreamConfiguration) {
        switch configuration.endpoint {
        case let .srtla(url, options), let .srt(url, options):
            let isSrtla = if case .srtla = configuration.endpoint { true } else { false }
            selectBondingImplementation(options.bondingImplementation)
            media.srtStartStream(
                isSrtla: isSrtla,
                url: url.absoluteString,
                reconnectTime: options.reconnectDelaySeconds,
                targetBitrate: UInt32(clamping: configuration.video.targetBitrate),
                adaptiveBitrateAlgorithm: Mapping.toSettings(options.adaptiveBitrate),
                latency: Int32(clamping: options.latencyMilliseconds),
                experimental: false, // upstream: debug flag
                overheadBandwidth: 25, // upstream: SettingsStreamSrt default
                maximumBandwidthFollowInput: true, // upstream: SettingsStreamSrt default
                mpegtsPacketsPerPacket: 7, // upstream: SettingsStreamSrt default
                packetPadding: false, // upstream: debug flag
                networkInterfaceNames: [], // custom interface names are phase 2
                connectionPriorities: Mapping.toSettings(options.bondingPriorities),
                dnsLookupStrategy: .system // upstream: SettingsStreamSrt default
            )
            // Must come AFTER srtStartStream: the AdaptiveBitrate object is
            // created inside it, and setAdaptiveBitrateSettings is a no-op on
            // nil (mirrors Moblin: srtStartStream then updateAdaptiveBitrateSrt).
            if let settings = Mapping.adaptiveBitrateSettings(options.adaptiveBitrate) {
                media.setAdaptiveBitrateSettings(settings: settings)
            }
        case let .rtmp(url):
            media.rtmpStartStream(
                url: url.absoluteString,
                targetBitrate: UInt32(clamping: configuration.video.targetBitrate),
                adaptiveBitrate: false // RTMP ABR is upstream-experimental; phase 2
            )
        }
    }

    /// Choose the bonding transport before `srtStartStream` (which reads the
    /// override inside `srtInitStream`). `.moblinSRTLA` clears the override so
    /// Media builds its vendored `SrtlaClient`; `.irltp` injects the Rust-backed
    /// adapter bonding across the cellular + wifi interfaces.
    private func selectBondingImplementation(_ implementation: BondingImplementation) {
        switch implementation {
        case .moblinSRTLA:
            media.bondingOverride = nil
        case .irltp:
            let links: [IRLTPBondingClient.Link] = [
                .init(interfaceType: .cellular),
                .init(interfaceType: .wifi),
            ]
            media.bondingOverride = { delegate in
                IRLTPBondingAdapter(delegate: delegate, links: links)
            }
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
        stats.totalBytesSent = totalBytesBase + media.streamTotal()
        stats.currentBitrate = Int(media.getVideoStreamBitrate(bitrate: UInt32(clamping: max(0, stats.targetBitrate))))
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
