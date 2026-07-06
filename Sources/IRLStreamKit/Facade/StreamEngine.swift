// Public API surface of IRLStreamKit.
//
// CONTAINMENT RULE: no identifier from Vendor/ or Shim/ may appear in any
// `public` or `package` signature. Upstream churn is absorbed by exactly two
// internal files: MediaDelegateAdapter.swift and Mapping.swift.

import CoreGraphics
import Foundation

// MARK: - Errors (Equatable value types so tests assert with ==)

public enum StreamConfigurationError: Error, Equatable, Sendable {
    case invalidURL(String)
    case unsupportedScheme(String)
    case bitrateOutOfRange(Int)
}

public enum StreamEngineError: Error, Equatable, Sendable {
    case cameraPermissionDenied
    case microphonePermissionDenied
    case cameraUnavailable
    case captureSessionFailed(String)
    case notInSession
    case alreadyLive
    case invalidConfiguration(StreamConfigurationError)
    case connectionFailed(String)
}

// MARK: - Configuration (Sendable value types only)

public struct StreamConfiguration: Equatable, Sendable {
    public var endpoint: StreamEndpoint
    public var video: VideoConfiguration
    public var audio: AudioConfiguration

    public init(endpoint: StreamEndpoint,
                video: VideoConfiguration = VideoConfiguration(),
                audio: AudioConfiguration = AudioConfiguration()) {
        self.endpoint = endpoint
        self.video = video
        self.audio = audio
    }
}

/// SRTLA bonding is a first-class case, not a flag — upstream's `isSrtla:`
/// bool never leaks.
public enum StreamEndpoint: Equatable, Sendable {
    case srtla(url: URL, options: SRTOptions)
    case srt(url: URL, options: SRTOptions)
    case rtmp(url: URL)

    // Enum cases can't have default associated values; factories fill defaults.
    public static func srtla(url: URL) -> StreamEndpoint { .srtla(url: url, options: SRTOptions()) }
    public static func srt(url: URL) -> StreamEndpoint { .srt(url: url, options: SRTOptions()) }
}

public struct SRTOptions: Equatable, Sendable {
    public var latencyMilliseconds: Int
    public var adaptiveBitrate: AdaptiveBitratePreset
    public var bondingPriorities: BondingPriorities
    public var reconnectDelaySeconds: Double

    public init(latencyMilliseconds: Int = 3000, // pinned: upstream defaultSrtLatency
                adaptiveBitrate: AdaptiveBitratePreset = .belabox,
                bondingPriorities: BondingPriorities = .automatic,
                reconnectDelaySeconds: Double = 5) {
        self.latencyMilliseconds = latencyMilliseconds
        self.adaptiveBitrate = adaptiveBitrate
        self.bondingPriorities = bondingPriorities
        self.reconnectDelaySeconds = reconnectDelaySeconds
    }
}

/// Presets only; the raw adaptive-bitrate tuning knobs stay internal.
public enum AdaptiveBitratePreset: String, CaseIterable, Equatable, Sendable {
    case off, belabox, fastIRL, slowIRL
}

/// Value replacement for the internal connection-priorities settings class.
public struct BondingPriorities: Equatable, Sendable {
    public struct Link: Equatable, Sendable, Identifiable {
        public enum Interface: String, Equatable, Hashable, Sendable, CaseIterable {
            case cellular, wifi, ethernet
        }

        public var id: Interface { interface }
        public var interface: Interface
        public var priority: Int // 1...10, higher wins
        public var enabled: Bool

        public init(interface: Interface, priority: Int = 1, enabled: Bool = true) {
            self.interface = interface
            self.priority = priority
            self.enabled = enabled
        }
    }

    public var enabled: Bool
    public var links: [Link]

    public static let automatic = BondingPriorities(enabled: false, links: [])

    public init(enabled: Bool, links: [Link]) {
        self.enabled = enabled
        self.links = links
    }
}

public struct VideoConfiguration: Equatable, Sendable {
    public var resolution: StreamResolution
    public var frameRate: Int
    public var codec: StreamCodec
    public var targetBitrate: Int // bits per second
    public var isPortrait: Bool

    public init(resolution: StreamResolution = .fhd1080p,
                frameRate: Int = 30,
                codec: StreamCodec = .hevc,
                targetBitrate: Int = 6_000_000,
                isPortrait: Bool = false) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
        self.targetBitrate = targetBitrate
        self.isPortrait = isPortrait
    }
}

/// Deliberately narrower than upstream's 12-case resolution list — only what
/// UX IRL's go-live sheet offers. Widening later is non-breaking.
public enum StreamResolution: String, CaseIterable, Equatable, Sendable {
    case uhd2160p, qhd1440p, fhd1080p, hd720p, sd540p, sd480p, sd360p

    public var dimensions: CGSize {
        switch self {
        case .uhd2160p: CGSize(width: 3840, height: 2160)
        case .qhd1440p: CGSize(width: 2560, height: 1440)
        case .fhd1080p: CGSize(width: 1920, height: 1080)
        case .hd720p: CGSize(width: 1280, height: 720)
        case .sd540p: CGSize(width: 960, height: 540)
        case .sd480p: CGSize(width: 854, height: 480)
        case .sd360p: CGSize(width: 640, height: 360)
        }
    }
}

public enum StreamCodec: String, CaseIterable, Equatable, Sendable {
    case hevc
    case h264
}

public struct AudioConfiguration: Equatable, Sendable {
    public var bitrate: Int // bits per second

    public init(bitrate: Int = 128_000) {
        self.bitrate = bitrate
    }
}

public enum CameraSelection: String, CaseIterable, Equatable, Sendable {
    case back, front
}

// MARK: - State (one Equatable snapshot; the single source of truth)

public enum StreamPhase: Equatable, Sendable {
    case idle // no capture session
    case previewing // camera live, not streaming
    case connecting
    case live(since: Date)
    case reconnecting(reason: String)

    public var isLive: Bool {
        if case .live = self { return true }
        if case .reconnecting = self { return true }
        return false
    }
}

public struct StreamStatistics: Equatable, Sendable {
    public var currentBitrate: Int = 0 // encoder actual, post-ABR
    public var targetBitrate: Int = 0
    public var transportBitrate: Int = 0 // SRT(LA) link estimate, bonded total
    public var encoderFps: Int = 0
    public var totalBytesSent: Int64 = 0

    public init() {}
}

/// Value snapshot of a bonded connection with UI-ready share.
public struct BondingLink: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String // "Cellular", "WiFi", relay name
    public let bytesSent: UInt64
    public let shareOfTotal: Double // 0...1, precomputed by the facade
    public let rttMilliseconds: Int?

    public init(name: String, bytesSent: UInt64, shareOfTotal: Double, rttMilliseconds: Int?) {
        self.name = name
        self.bytesSent = bytesSent
        self.shareOfTotal = shareOfTotal
        self.rttMilliseconds = rttMilliseconds
    }
}

public struct AudioLevel: Equatable, Sendable {
    /// nil == muted. Upstream signals mute with a Float.nan sentinel; the
    /// facade maps it away (NaN would also break Equatable).
    public var decibels: Float?
    public var channels: Int

    public init(decibels: Float? = nil, channels: Int = 0) {
        self.decibels = decibels
        self.channels = channels
    }
}

public struct StreamEngineState: Equatable, Sendable {
    public var phase: StreamPhase = .idle
    public var camera: CameraSelection = .back
    public var isMicMuted: Bool = false
    public var stats: StreamStatistics = .init()
    public var bondingLinks: [BondingLink] = []
    public var audioLevel: AudioLevel = .init()

    public init() {}
}

// MARK: - Events (discrete happenings: toasts, haptics, logging — not layout)

/// Closed, product-shaped set. Upstream delegate methods with no case here are
/// silently absorbed by the internal adapter. New cases are additive minor
/// releases — consumers must switch with `default:`.
public enum StreamEvent: Equatable, Sendable {
    case phaseChanged(StreamPhase)
    case statsUpdated(StreamStatistics)
    case bondingUpdated([BondingLink])
    case audioLevelUpdated(AudioLevel)
    case micMuteChanged(isMuted: Bool)
    case cameraChanged(CameraSelection)
    case adaptiveBitrateChanged(bitsPerSecond: Int)
    case encoderResolutionChanged(width: Int, height: Int)
    case cameraAttachFailed
    case failed(StreamEngineError)
}

// MARK: - The protocol UX IRL view models depend on
// No AVFoundation, no UIKit, no vendor types — a fake needs zero hardware.

@MainActor
public protocol StreamEngine: AnyObject {
    /// Snapshot value. Both shipped implementations are @Observable classes,
    /// so SwiftUI observation works even through `any StreamEngine`.
    var state: StreamEngineState { get }

    /// Change notifications for toasts/haptics/logging. Each call returns a
    /// fresh stream. `state` is the source of truth — never reconstruct state
    /// from events alone.
    func events() -> AsyncStream<StreamEvent>

    // Session lifecycle (preview-before-live; endStream keeps preview alive)
    /// Requests camera+mic permission, attaches the camera, begins rendering
    /// into any bound preview view. Idempotent.
    func startSession(camera: CameraSelection) async throws(StreamEngineError)
    /// Tears down capture. No-op while `state.phase.isLive`.
    func stopSession()

    // Streaming lifecycle
    /// Validates config, configures the internal net stream (SRT/SRTLA/RTMP),
    /// connects, and starts the internal stats + adaptive-bitrate tick loops.
    func goLive(_ configuration: StreamConfiguration) async throws(StreamEngineError)
    /// Stops the network stream; capture + preview keep running.
    func endStream()

    // Live controls (synchronous fire-and-forget; results land in state/events)
    func setCamera(_ camera: CameraSelection)
    func setMicMuted(_ muted: Bool)
    func setTargetBitrate(_ bitsPerSecond: Int)
}
