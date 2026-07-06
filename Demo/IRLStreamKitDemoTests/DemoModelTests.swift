// Drives DemoModel with FakeStreamEngine from IRLStreamKitTestSupport — the
// proof that an external consumer can TDD its view models against the fake,
// exactly as UX IRL will.

import Foundation
import IRLStreamKit
import IRLStreamKitTestSupport
import Testing
@testable import IRLStreamKitDemo

@MainActor
struct DemoModelTests {
    private func makeModel() -> (DemoModel, FakeStreamEngine) {
        let fake = FakeStreamEngine()
        let model = DemoModel(engine: fake)
        return (model, fake)
    }

    @Test func fakeHasNoPreviewSource() {
        let (model, _) = makeModel()
        #expect(model.previewSource == nil)
    }

    @Test func toggleSessionFromIdleStartsCamera() async {
        let (model, fake) = makeModel()

        model.toggleSession()
        await waitForCommands(fake, count: 1)

        #expect(fake.commands == [.startSession(.back)])
        #expect(fake.state.phase == .previewing)
    }

    @Test func toggleStreamBuildsConfigurationFromSettings() async throws {
        let (model, fake) = makeModel()
        try await fake.startSession(camera: .back)

        model.settings.endpointKind = .srtla
        model.settings.urlString = "srtla://ingest.example.com:5000?streamid=abc"
        model.settings.latencyMilliseconds = 4000
        model.settings.reconnectDelaySeconds = 7
        model.settings.adaptiveBitrate = .slowIRL
        model.settings.manualBondingPriorities = true
        model.settings.bondingLinks = [
            .init(interfaceRaw: "cellular", priority: 9, enabled: true),
            .init(interfaceRaw: "wifi", priority: 2, enabled: false),
        ]
        model.settings.resolution = .hd720p
        model.settings.frameRate = 60
        model.settings.codec = .h264
        model.settings.targetBitrateMegabits = 4.5
        model.settings.audioBitrateKilobits = 192
        model.settings.isPortrait = false

        model.toggleStream()
        await waitForCommands(fake, count: 2)

        let expected = StreamConfiguration(
            endpoint: .srtla(
                url: URL(string: "srtla://ingest.example.com:5000?streamid=abc")!,
                options: SRTOptions(
                    latencyMilliseconds: 4000,
                    adaptiveBitrate: .slowIRL,
                    bondingPriorities: BondingPriorities(enabled: true, links: [
                        .init(interface: .cellular, priority: 9, enabled: true),
                        .init(interface: .wifi, priority: 2, enabled: false),
                    ]),
                    reconnectDelaySeconds: 7
                )
            ),
            video: VideoConfiguration(
                resolution: .hd720p,
                frameRate: 60,
                codec: .h264,
                targetBitrate: 4_500_000,
                isPortrait: false
            ),
            audio: AudioConfiguration(bitrate: 192_000)
        )
        #expect(fake.commands.last == .goLive(expected))
        #expect(fake.state.phase == .connecting)
    }

    @Test func invalidURLIsRejectedBeforeReachingTheEngine() async throws {
        let (model, fake) = makeModel()
        try await fake.startSession(camera: .back)
        model.settings.urlString = ""

        model.toggleStream()

        #expect(model.lastError != nil)
        #expect(fake.commands == [.startSession(.back)])
    }

    @Test func scriptedGoLiveFailureSurfacesError() async throws {
        let (model, fake) = makeModel()
        try await fake.startSession(camera: .back)
        fake.goLiveResult = .failure(.connectionFailed("timeout"))
        model.settings.urlString = "srtla://ingest.example.com:5000"

        model.toggleStream()
        await waitForCommands(fake, count: 2)
        await Task.yield()

        #expect(model.lastError == "connection failed: timeout")
        #expect(fake.state.phase == .previewing)
    }

    @Test func muteAndCameraControlsForwardToEngine() async throws {
        let (model, fake) = makeModel()
        try await fake.startSession(camera: .back)

        model.toggleMute()
        model.flipCamera()

        #expect(fake.commands.suffix(2) == [.setMicMuted(true), .setCamera(.front)])
        #expect(fake.state.isMicMuted)
        #expect(fake.state.camera == .front)
    }

    @Test func bitrateSliderChangesTargetWhileLive() async throws {
        let (model, fake) = makeModel()
        try await fake.startSession(camera: .back)
        fake.emit(.phaseChanged(.live(since: .distantPast)))

        model.setTargetBitrate(megabits: 2.5)

        #expect(fake.commands.last == .setTargetBitrate(2_500_000))
        #expect(fake.state.stats.targetBitrate == 2_500_000)
    }

    @Test func modelLogsEventsWhileASecondSubscriberAlsoReceivesThem() async throws {
        let (model, fake) = makeModel()
        let second = fake.events()

        fake.emit(.micMuteChanged(isMuted: true))

        var iterator = second.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == .micMuteChanged(isMuted: true))

        // The model's log fills via its own consumer task.
        for _ in 0 ..< 20 where model.log.isEmpty {
            await Task.yield()
        }
        #expect(model.log.contains { $0.text == "mic muted" })
    }

    @Test func endpointFactoriesFillDefaultOptions() {
        let url = URL(string: "srtla://ingest.example.com:5000")!
        #expect(StreamEndpoint.srtla(url: url) == .srtla(url: url, options: SRTOptions()))
        #expect(StreamEndpoint.srt(url: url) == .srt(url: url, options: SRTOptions()))
    }

    // toggleSession/toggleStream dispatch through Tasks; spin until the fake
    // has recorded the expected number of commands (deterministic — the fake
    // itself is synchronous, only the model's Task hop is awaited).
    private func waitForCommands(_ fake: FakeStreamEngine, count: Int) async {
        for _ in 0 ..< 50 where fake.commands.count < count {
            await Task.yield()
        }
    }
}
