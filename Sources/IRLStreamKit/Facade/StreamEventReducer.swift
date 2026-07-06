// Pure, total state derivation: state x event -> state. `package` (not
// public) — visible to IRLStreamKitTestSupport and the package's own tests,
// but not consumer API. Both IRLStreamEngine and FakeStreamEngine funnel
// every state mutation through this, so fake and real cannot diverge.

package enum StreamEventReducer {
    package static func reduce(_ state: StreamEngineState,
                               _ event: StreamEvent) -> StreamEngineState {
        var state = state
        switch event {
        case let .phaseChanged(phase):
            state.phase = phase
            switch phase {
            case .idle, .previewing:
                state.stats = StreamStatistics()
                state.bondingLinks = []
            case .connecting, .live, .reconnecting:
                break
            }
        case let .statsUpdated(stats):
            state.stats = stats
        case let .bondingUpdated(links):
            state.bondingLinks = links
        case let .audioLevelUpdated(level):
            state.audioLevel = level
        case let .micMuteChanged(isMuted):
            state.isMicMuted = isMuted
        case let .cameraChanged(camera):
            state.camera = camera
        case let .adaptiveBitrateChanged(bitsPerSecond):
            state.stats.currentBitrate = bitsPerSecond
        case .encoderResolutionChanged, .cameraAttachFailed, .failed:
            break
        }
        return state
    }
}
