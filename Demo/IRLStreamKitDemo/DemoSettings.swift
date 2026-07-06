// UserDefaults-backed stream settings for the demo. Everything maps to
// public IRLStreamKit configuration types.

import Foundation
import IRLStreamKit

struct DemoSettings: Codable, Equatable {
    enum EndpointKind: String, Codable, CaseIterable, Identifiable {
        case srtla, srt, rtmp
        var id: String { rawValue }
    }

    var endpointKind: EndpointKind = .srtla
    var urlString: String = "srtla://"
    var latencyMilliseconds: Int = 3000
    var adaptiveBitrateRaw: String = AdaptiveBitratePreset.belabox.rawValue
    var resolutionRaw: String = StreamResolution.fhd1080p.rawValue
    var frameRate: Int = 30
    var codecRaw: String = StreamCodec.hevc.rawValue
    var targetBitrateMegabits: Double = 6
    var isPortrait: Bool = true

    var adaptiveBitrate: AdaptiveBitratePreset {
        get { AdaptiveBitratePreset(rawValue: adaptiveBitrateRaw) ?? .belabox }
        set { adaptiveBitrateRaw = newValue.rawValue }
    }

    var resolution: StreamResolution {
        get { StreamResolution(rawValue: resolutionRaw) ?? .fhd1080p }
        set { resolutionRaw = newValue.rawValue }
    }

    var codec: StreamCodec {
        get { StreamCodec(rawValue: codecRaw) ?? .hevc }
        set { codecRaw = newValue.rawValue }
    }

    func buildConfiguration() -> StreamConfiguration? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let options = SRTOptions(
            latencyMilliseconds: latencyMilliseconds,
            adaptiveBitrate: adaptiveBitrate
        )
        let endpoint: StreamEndpoint = switch endpointKind {
        case .srtla: .srtla(url: url, options: options)
        case .srt: .srt(url: url, options: options)
        case .rtmp: .rtmp(url: url)
        }
        return StreamConfiguration(
            endpoint: endpoint,
            video: VideoConfiguration(
                resolution: resolution,
                frameRate: frameRate,
                codec: codec,
                targetBitrate: Int(targetBitrateMegabits * 1_000_000),
                isPortrait: isPortrait
            )
        )
    }

    // MARK: - Persistence

    private static let key = "demo.settings"

    static func load() -> DemoSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(DemoSettings.self, from: data)
        else {
            return DemoSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
