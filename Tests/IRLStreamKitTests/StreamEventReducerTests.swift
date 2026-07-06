import Testing
@testable import IRLStreamKit

struct StreamEventReducerTests {
    @Test func phaseChangeToPreviewingResetsStatsAndBonding() {
        var state = StreamEngineState()
        state.phase = .live(since: .distantPast)
        state.stats.transportBitrate = 5_000_000
        state.bondingLinks = [BondingLink(name: "Cellular", bytesSent: 10, shareOfTotal: 1, rttMilliseconds: 40)]

        let next = StreamEventReducer.reduce(state, .phaseChanged(.previewing))

        #expect(next.phase == .previewing)
        #expect(next.stats == StreamStatistics())
        #expect(next.bondingLinks.isEmpty)
    }

    @Test func phaseChangeToLiveKeepsStats() {
        var state = StreamEngineState()
        state.phase = .connecting
        state.stats.targetBitrate = 6_000_000

        let next = StreamEventReducer.reduce(state, .phaseChanged(.live(since: .distantPast)))

        #expect(next.phase.isLive)
        #expect(next.stats.targetBitrate == 6_000_000)
    }

    @Test func micMuteChangeUpdatesFlagOnly() {
        let state = StreamEngineState()

        let next = StreamEventReducer.reduce(state, .micMuteChanged(isMuted: true))

        #expect(next.isMicMuted)
        #expect(next.phase == .idle)
    }

    @Test func adaptiveBitrateUpdatesCurrentBitrate() {
        var state = StreamEngineState()
        state.stats.targetBitrate = 6_000_000

        let next = StreamEventReducer.reduce(state, .adaptiveBitrateChanged(bitsPerSecond: 2_500_000))

        #expect(next.stats.currentBitrate == 2_500_000)
        #expect(next.stats.targetBitrate == 6_000_000)
    }

    @Test func cameraChangedUpdatesCamera() {
        let state = StreamEngineState()

        let next = StreamEventReducer.reduce(state, .cameraChanged(.front))

        #expect(next.camera == .front)
    }

    @Test func eventOnlyCasesLeaveStateUntouched() {
        var state = StreamEngineState()
        state.phase = .live(since: .distantPast)
        state.stats.encoderFps = 30

        for event: StreamEvent in [
            .encoderResolutionChanged(width: 1280, height: 720),
            .cameraAttachFailed,
            .failed(.connectionFailed("timeout")),
        ] {
            #expect(StreamEventReducer.reduce(state, event) == state)
        }
    }
}
