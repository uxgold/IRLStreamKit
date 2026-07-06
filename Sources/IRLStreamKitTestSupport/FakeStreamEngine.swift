// Shipped fake for consumer TDD — view models import this instead of
// hand-rolling fakes. It applies the SAME package reducer as the production
// engine and enforces the same phase machine, so fake and real cannot
// diverge on state derivation or lifecycle contract.

import Foundation
import IRLStreamKit
import Observation

@MainActor
@Observable
public final class FakeStreamEngine: StreamEngine {
    /// Every command the SUT issued, in order — assert with ==.
    public enum Command: Equatable, Sendable {
        case startSession(CameraSelection)
        case stopSession
        case goLive(StreamConfiguration)
        case endStream
        case setCamera(CameraSelection)
        case setMicMuted(Bool)
        case setTargetBitrate(Int)
    }

    public private(set) var commands: [Command] = []
    public private(set) var state = StreamEngineState()

    /// Script failures, e.g. `fake.goLiveResult = .failure(.connectionFailed("timeout"))`.
    public var startSessionResult: Result<Void, StreamEngineError> = .success(())
    public var goLiveResult: Result<Void, StreamEngineError> = .success(())

    @ObservationIgnored private let broadcaster = EventBroadcaster()

    public init() {}

    /// Tests drive the world: applies the same package reducer synchronously
    /// and yields to event streams before returning. Fully deterministic.
    public func emit(_ event: StreamEvent) {
        state = StreamEventReducer.reduce(state, event)
        broadcaster.yield(event)
    }

    public func events() -> AsyncStream<StreamEvent> {
        broadcaster.subscribe()
    }

    public func startSession(camera: CameraSelection) async throws(StreamEngineError) {
        commands.append(.startSession(camera))
        guard case .idle = state.phase else {
            // Same contract as the real engine: idempotent, but honors a
            // camera switch while previewing.
            if case .previewing = state.phase, camera != state.camera {
                emit(.cameraChanged(camera))
            }
            return
        }
        if case let .failure(error) = startSessionResult {
            throw error
        }
        emit(.cameraChanged(camera))
        emit(.phaseChanged(.previewing))
    }

    public func stopSession() {
        commands.append(.stopSession)
        switch state.phase {
        case .connecting:
            emit(.phaseChanged(.previewing)) // endStream, as the real engine does
        case .previewing:
            break
        case .idle, .live, .reconnecting:
            return // no-op, same contract as the real engine
        }
        emit(.phaseChanged(.idle))
    }

    public func goLive(_ configuration: StreamConfiguration) async throws(StreamEngineError) {
        commands.append(.goLive(configuration))
        switch state.phase {
        case .previewing:
            break
        case .idle:
            throw StreamEngineError.notInSession
        case .connecting, .live, .reconnecting:
            throw StreamEngineError.alreadyLive
        }
        if case let .failure(error) = goLiveResult {
            throw error
        }
        // Same emission order as the real engine: stats first, then phase.
        var stats = StreamStatistics()
        stats.targetBitrate = configuration.video.targetBitrate
        stats.currentBitrate = configuration.video.targetBitrate
        emit(.statsUpdated(stats))
        emit(.phaseChanged(.connecting))
    }

    public func endStream() {
        commands.append(.endStream)
        guard state.phase.isLive || state.phase == .connecting else {
            return
        }
        emit(.phaseChanged(.previewing))
    }

    public func setCamera(_ camera: CameraSelection) {
        commands.append(.setCamera(camera))
        guard camera != state.camera else {
            return
        }
        emit(.cameraChanged(camera))
    }

    public func setMicMuted(_ muted: Bool) {
        commands.append(.setMicMuted(muted))
        emit(.micMuteChanged(isMuted: muted))
    }

    public func setTargetBitrate(_ bitsPerSecond: Int) {
        commands.append(.setTargetBitrate(bitsPerSecond))
        var stats = state.stats
        stats.targetBitrate = bitsPerSecond
        emit(.statsUpdated(stats))
    }
}
