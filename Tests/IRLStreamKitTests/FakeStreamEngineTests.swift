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

        await #expect(throws: StreamEngineError.connectionFailed("timeout")) {
            try await fake.goLive(config)
        }
        #expect(fake.commands == [.goLive(config)])
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
