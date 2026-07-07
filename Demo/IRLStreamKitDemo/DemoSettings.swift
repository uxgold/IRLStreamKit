// UserDefaults-backed stream settings for the demo. Everything maps to
// public IRLStreamKit configuration types.

import Foundation
import IRLStreamKit

struct DemoSettings: Codable, Equatable {
    enum EndpointKind: String, Codable, CaseIterable, Identifiable {
        case srtla, srt, rtmp
        var id: String { rawValue }
    }

    struct BondingLinkSetting: Codable, Equatable, Identifiable {
        var interfaceRaw: String
        var priority: Int = 1
        var enabled: Bool = true

        var id: String { interfaceRaw }

        var interface: BondingPriorities.Link.Interface? {
            BondingPriorities.Link.Interface(rawValue: interfaceRaw)
        }
    }

    var endpointKind: EndpointKind = .srtla
    var urlString: String = "srtla://"
    var latencyMilliseconds: Int = 3000
    var reconnectDelaySeconds: Double = 5
    var bondingImplementationRaw: String = BondingImplementation.moblinSRTLA.rawValue
    var adaptiveBitrateRaw: String = AdaptiveBitratePreset.belabox.rawValue
    var manualBondingPriorities: Bool = false
    var bondingLinks: [BondingLinkSetting] = BondingPriorities.Link.Interface.allCases.map {
        BondingLinkSetting(interfaceRaw: $0.rawValue)
    }
    var resolutionRaw: String = StreamResolution.fhd1080p.rawValue
    var frameRate: Int = 30
    var codecRaw: String = StreamCodec.hevc.rawValue
    var targetBitrateMegabits: Double = 6
    var audioBitrateKilobits: Int = 128
    var isPortrait: Bool = true

    var adaptiveBitrate: AdaptiveBitratePreset {
        get { AdaptiveBitratePreset(rawValue: adaptiveBitrateRaw) ?? .belabox }
        set { adaptiveBitrateRaw = newValue.rawValue }
    }

    var bondingImplementation: BondingImplementation {
        get { BondingImplementation(rawValue: bondingImplementationRaw) ?? .moblinSRTLA }
        set { bondingImplementationRaw = newValue.rawValue }
    }

    var resolution: StreamResolution {
        get { StreamResolution(rawValue: resolutionRaw) ?? .fhd1080p }
        set { resolutionRaw = newValue.rawValue }
    }

    var codec: StreamCodec {
        get { StreamCodec(rawValue: codecRaw) ?? .hevc }
        set { codecRaw = newValue.rawValue }
    }

    var bondingPriorities: BondingPriorities {
        guard manualBondingPriorities else {
            return .automatic
        }
        return BondingPriorities(
            enabled: true,
            links: bondingLinks.compactMap { link in
                link.interface.map {
                    BondingPriorities.Link(interface: $0, priority: link.priority, enabled: link.enabled)
                }
            }
        )
    }

    func buildConfiguration() -> StreamConfiguration? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let options = SRTOptions(
            latencyMilliseconds: latencyMilliseconds,
            adaptiveBitrate: adaptiveBitrate,
            bondingPriorities: bondingPriorities,
            reconnectDelaySeconds: reconnectDelaySeconds,
            bondingImplementation: bondingImplementation
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
            ),
            audio: AudioConfiguration(bitrate: audioBitrateKilobits * 1000)
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
