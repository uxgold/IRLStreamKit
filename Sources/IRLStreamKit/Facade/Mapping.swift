// One-way converters from public value types to the internal Settings* shims
// and engine types. All switches are exhaustive so upstream changes fail
// compilation inside the package, never in a consumer. Moblin-app-only
// parameters are pinned here, each documented with its upstream origin.

import CoreMedia
import Foundation
import VideoToolbox

enum Mapping {
    static func toSettings(_ resolution: StreamResolution) -> SettingsStreamResolution {
        switch resolution {
        case .uhd2160p: .r3840x2160
        case .qhd1440p: .r2560x1440
        case .fhd1080p: .r1920x1080
        case .hd720p: .r1280x720
        case .sd540p: .r960x540
        case .sd480p: .r854x480
        case .sd360p: .r640x360
        }
    }

    /// Capture size per resolution — mirrors ModelStream.setStreamResolution
    /// (downscale-from-larger-sensor-mode cases included).
    static func captureSize(_ resolution: StreamResolution) -> CGSize {
        switch resolution {
        case .uhd2160p: CGSize(width: 3840, height: 2160)
        case .qhd1440p: CGSize(width: 3840, height: 2160) // 4K capture, downscale
        case .fhd1080p: CGSize(width: 1920, height: 1080)
        case .hd720p: CGSize(width: 1280, height: 720)
        case .sd540p: CGSize(width: 960, height: 540)
        case .sd480p: CGSize(width: 960, height: 540) // 540p capture, downscale
        case .sd360p: CGSize(width: 960, height: 540) // 540p capture, downscale
        }
    }

    static func streamDimensions(_ video: VideoConfiguration) -> CMVideoDimensions {
        Mapping.toSettings(video.resolution).dimensions(portrait: video.isPortrait)
    }

    /// Codec -> VideoToolbox profile — mirrors ModelStream.setStreamCodec
    /// (h264 high profile, HEVC main; HLG/Main10 is out of MVP scope).
    static func videoProfile(_ codec: StreamCodec) -> CFString {
        switch codec {
        case .h264: kVTProfileLevel_H264_High_AutoLevel
        case .hevc: kVTProfileLevel_HEVC_Main_AutoLevel
        }
    }

    static func toSettings(_ preset: AdaptiveBitratePreset) -> SettingsStreamSrtAdaptiveBitrateAlgorithm? {
        switch preset {
        case .off: nil
        case .belabox: .belabox
        case .fastIRL: .fastIrl
        case .slowIRL: .slowIrl
        }
    }

    /// Preset -> tuning constants — mirrors Model.updateAdaptiveBitrateSrt
    /// (custom tuning is phase 2; presets use upstream constants unmodified).
    static func adaptiveBitrateSettings(_ preset: AdaptiveBitratePreset) -> AdaptiveBitrateSettings? {
        switch preset {
        case .off: nil
        case .belabox: adaptiveBitrateBelaboxSettings
        case .fastIRL: adaptiveBitrateFastSettings
        case .slowIRL: adaptiveBitrateSlowSettings
        }
    }

    /// Interface names match upstream's defaults ("Cellular"/"WiFi") plus
    /// "Ethernet"; SrtlaClient matches priorities by these names.
    static func toSettings(_ priorities: BondingPriorities) -> SettingsStreamSrtConnectionPriorities {
        let settings = SettingsStreamSrtConnectionPriorities()
        settings.enabled = priorities.enabled
        guard !priorities.links.isEmpty else {
            return settings // keep upstream's Cellular/WiFi defaults
        }
        settings.priorities = priorities.links.map { link in
            let priority = SettingsStreamSrtConnectionPriority(name: interfaceName(link.interface))
            priority.priority = link.priority
            priority.enabled = link.enabled
            return priority
        }
        return settings
    }

    private static func interfaceName(_ interface: BondingPriorities.Link.Interface) -> String {
        switch interface {
        case .cellular: "Cellular"
        case .wifi: "WiFi"
        case .ethernet: "Ethernet"
        }
    }

    static func bondingLinks(_ connections: [BondingConnection]) -> [BondingLink] {
        let total = connections.reduce(UInt64(0)) { $0 + $1.usage }
        return connections.map { connection in
            BondingLink(
                name: connection.name,
                bytesSent: connection.usage,
                shareOfTotal: total > 0 ? Double(connection.usage) / Double(total) : 0,
                rttMilliseconds: connection.rtt
            )
        }
    }

    static func netStreamProtocol(_ endpoint: StreamEndpoint?) -> SettingsStreamProtocol {
        switch endpoint {
        case .srt, .srtla: .srt
        case .rtmp, nil: .rtmp
        }
    }
}

enum ConfigurationValidator {
    static func validate(_ configuration: StreamConfiguration) -> StreamConfigurationError? {
        switch configuration.endpoint {
        case let .srtla(url, _), let .srt(url, _):
            guard let scheme = url.scheme?.lowercased(), scheme == "srt" || scheme == "srtla" else {
                return .unsupportedScheme(configuration.endpoint.urlForValidation.scheme ?? "")
            }
            guard url.host() != nil else {
                return .invalidURL(url.absoluteString)
            }
        case let .rtmp(url):
            guard let scheme = url.scheme?.lowercased(), scheme == "rtmp" || scheme == "rtmps" else {
                return .unsupportedScheme(url.scheme ?? "")
            }
            guard url.host() != nil else {
                return .invalidURL(url.absoluteString)
            }
        }
        guard (100_000 ... 50_000_000).contains(configuration.video.targetBitrate) else {
            return .bitrateOutOfRange(configuration.video.targetBitrate)
        }
        return nil
    }
}

extension StreamEndpoint {
    var urlForValidation: URL {
        switch self {
        case let .srtla(url, _), let .srt(url, _), let .rtmp(url):
            url
        }
    }
}
