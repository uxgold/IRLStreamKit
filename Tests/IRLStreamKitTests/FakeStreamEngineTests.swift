import Foundation
import IRLStreamKit
import IRLStreamKitTestSupport
import Testing

@MainActor
struct FakeStreamEngineTests {
    @Test func recordsCommandsInOrder() async throws {
        let fake = FakeStreamEngine()

        try await fake.startSession(camera: .front)
        fake.setMicMuted(true)
        fake.endStream()

        #expect(fake.commands == [.startSession(.front), .setMicMuted(true), .endStream])
    }

    @Test func startSessionMovesToPreviewing() async throws {
        let fake = FakeStreamEngine()

        try await fake.startSession(camera: .back)

        #expect(fake.state.phase == .previewing)
        #expect(fake.state.camera == .back)
    }

    @Test func scriptedGoLiveFailureThrows() async throws {
        let fake = FakeStreamEngine()
        fake.goLiveResult = .failure(.connectionFailed("timeout"))
        let config = StreamConfiguration(endpoint: .srtla(url: URL(string: "srt://example.com:5000")!))

        try await fake.startSession(camera: .back)
        await #expect(throws: StreamEngineError.connectionFailed("timeout")) {
            try await fake.goLive(config)
        }
        #expect(fake.commands == [.startSession(.back), .goLive(config)])
    }

    @Test func goLiveFromIdleThrowsNotInSession() async {
        let fake = FakeStreamEngine()
        let config = StreamConfiguration(endpoint: .srtla(url: URL(string: "srt://example.com:5000")!))

        await #expect(throws: StreamEngineError.notInSession) {
            try await fake.goLive(config)
        }
    }

    @Test func lifecycleMatchesRealEngineContract() async throws {
        let fake = FakeStreamEngine()
        let config = StreamConfiguration(endpoint: .srtla(url: URL(string: "srt://example.com:5000")!))

        try await fake.startSession(camera: .back)
        try await fake.goLive(config)
        #expect(fake.state.phase == .connecting)
        #expect(fake.state.stats.targetBitrate == config.video.targetBitrate)

        fake.stopSession() // no-op-ish: ends the pending connection, stays out of live teardown
        #expect(fake.state.phase == .idle)

        fake.endStream() // no-op from idle
        #expect(fake.state.phase == .idle)
    }

    @Test func emittedEventsReachSubscribers() async throws {
        let fake = FakeStreamEngine()
        let stream = fake.events()

        fake.emit(.micMuteChanged(isMuted: true))

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event == .micMuteChanged(isMuted: true))
        #expect(fake.state.isMicMuted)
    }

    @Test func fakeAndReducerCannotDiverge() {
        // The fake funnels every mutation through the package reducer, so a
        // manual replay of its emitted events must land on the same state.
        let fake = FakeStreamEngine()
        fake.emit(.cameraChanged(.front))
        fake.emit(.phaseChanged(.previewing))
        fake.emit(.micMuteChanged(isMuted: true))

        var replayed = StreamEngineState()
        for event: StreamEvent in [
            .cameraChanged(.front),
            .phaseChanged(.previewing),
            .micMuteChanged(isMuted: true),
        ] {
            replayed = StreamEventReducer.reduce(replayed, event)
        }

        #expect(fake.state == replayed)
    }
}
