// Shipped fake for consumer TDD — view models import this instead of
// hand-rolling fakes. It applies the SAME package reducer as the production
// engine, so fake and real cannot diverge on state derivation.

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
        if case let .failure(error) = startSessionResult {
            throw error
        }
        emit(.cameraChanged(camera))
        emit(.phaseChanged(.previewing))
    }

    public func stopSession() {
        commands.append(.stopSession)
        emit(.phaseChanged(.idle))
    }

    public func goLive(_ configuration: StreamConfiguration) async throws(StreamEngineError) {
        commands.append(.goLive(configuration))
        if case let .failure(error) = goLiveResult {
            throw error
        }
        emit(.phaseChanged(.connecting))
    }

    public func endStream() {
        commands.append(.endStream)
        emit(.phaseChanged(.previewing))
    }

    public func setCamera(_ camera: CameraSelection) {
        commands.append(.setCamera(camera))
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
