import CoreGraphics
import Foundation
import Testing
@testable import IRLStreamKit

struct MappingTests {
    @Test func resolutionMapsToUpstreamSettings() {
        #expect(Mapping.toSettings(.uhd2160p) == .r3840x2160)
        #expect(Mapping.toSettings(.qhd1440p) == .r2560x1440)
        #expect(Mapping.toSettings(.fhd1080p) == .r1920x1080)
        #expect(Mapping.toSettings(.hd720p) == .r1280x720)
        #expect(Mapping.toSettings(.sd540p) == .r960x540)
        #expect(Mapping.toSettings(.sd480p) == .r854x480)
        #expect(Mapping.toSettings(.sd360p) == .r640x360)
    }

    @Test func captureSizeMatchesUpstreamDownscaleTable() {
        // 1440p captures at 4K and downscales; 480p/360p capture at 540p.
        #expect(Mapping.captureSize(.qhd1440p) == CGSize(width: 3840, height: 2160))
        #expect(Mapping.captureSize(.sd480p) == CGSize(width: 960, height: 540))
        #expect(Mapping.captureSize(.sd360p) == CGSize(width: 960, height: 540))
        #expect(Mapping.captureSize(.fhd1080p) == CGSize(width: 1920, height: 1080))
    }

    @Test func portraitSwapsStreamDimensions() {
        let video = VideoConfiguration(resolution: .fhd1080p, isPortrait: true)
        let dims = Mapping.streamDimensions(video)
        #expect(dims.width == 1080)
        #expect(dims.height == 1920)
    }

    @Test func adaptiveBitratePresetMapping() {
        #expect(Mapping.toSettings(AdaptiveBitratePreset.off) == nil)
        #expect(Mapping.toSettings(AdaptiveBitratePreset.belabox) == .belabox)
        #expect(Mapping.toSettings(AdaptiveBitratePreset.fastIRL) == .fastIrl)
        #expect(Mapping.toSettings(AdaptiveBitratePreset.slowIRL) == .slowIrl)
        #expect(Mapping.adaptiveBitrateSettings(.off) == nil)
        #expect(Mapping.adaptiveBitrateSettings(.belabox) != nil)
    }

    @Test func bondingPrioritiesMapToNamedSettings() {
        let priorities = BondingPriorities(enabled: true, links: [
            .init(interface: .cellular, priority: 9, enabled: true),
            .init(interface: .wifi, priority: 1, enabled: false),
        ])

        let settings = Mapping.toSettings(priorities)

        #expect(settings.enabled)
        #expect(settings.priorities.count == 2)
        #expect(settings.priorities[0].name == "Cellular")
        #expect(settings.priorities[0].priority == 9)
        #expect(settings.priorities[1].name == "WiFi")
        #expect(settings.priorities[1].enabled == false)
    }

    @Test func automaticBondingKeepsUpstreamDefaults() {
        let settings = Mapping.toSettings(BondingPriorities.automatic)
        #expect(!settings.enabled)
        #expect(settings.priorities.map(\.name) == ["Cellular", "WiFi"])
    }

    @Test func bondingLinksComputeShareOfTotal() {
        let links = Mapping.bondingLinks([
            BondingConnection(name: "Cellular", usage: 750, rtt: 40),
            BondingConnection(name: "WiFi", usage: 250, rtt: nil),
        ])

        #expect(links[0].shareOfTotal == 0.75)
        #expect(links[1].shareOfTotal == 0.25)
        #expect(links[0].rttMilliseconds == 40)
        #expect(links[1].rttMilliseconds == nil)
    }

    @Test func validatorRejectsBadConfigs() {
        let srtConfig = StreamConfiguration(
            endpoint: .srt(url: URL(string: "rtmp://example.com/live")!)
        )
        #expect(ConfigurationValidator.validate(srtConfig) == .unsupportedScheme("rtmp"))

        let bitrateConfig = StreamConfiguration(
            endpoint: .srtla(url: URL(string: "srt://example.com:5000")!),
            video: VideoConfiguration(targetBitrate: 10)
        )
        #expect(ConfigurationValidator.validate(bitrateConfig) == .bitrateOutOfRange(10))

        let goodConfig = StreamConfiguration(
            endpoint: .srtla(url: URL(string: "srt://example.com:5000?streamid=abc")!)
        )
        #expect(ConfigurationValidator.validate(goodConfig) == nil)
    }
}
