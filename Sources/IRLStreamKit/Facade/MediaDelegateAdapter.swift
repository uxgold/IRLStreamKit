// The single churn-absorber for upstream's MediaDelegate. Media fires these
// callbacks from its processing/network queues; the adapter funnels the ones
// the facade cares about into ONE AsyncStream consumed by a single MainActor
// task in IRLStreamEngine (preserving ordering across the queue hop). When a
// Moblin sync adds/renames a MediaDelegate method, THIS file fails to compile
// — the public surface never moves.

import CoreMedia
import Foundation
import os

/// Internal signals produced by MediaDelegate callbacks, ordered as received.
enum EngineSignal {
    case connected
    case disconnected(reason: String)
    case audioMuteChanged
    case attachCameraError
    case captureSessionError(String)
    case encoderResolutionChanged(CGSize)
    case fps(Int)
    case mediaError(String)
}

/// A signal stamped with the stream generation current when it was produced.
/// The engine bumps the generation on every stream transition and drops
/// connection signals from earlier generations (they belong to a stream that
/// has already been stopped).
struct StampedSignal {
    let generation: Int
    let signal: EngineSignal
}

final class MediaDelegateAdapter: MediaDelegate {
    private let signals: AsyncStream<StampedSignal>.Continuation
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    init(signals: AsyncStream<StampedSignal>.Continuation) {
        self.signals = signals
    }

    /// Called by the engine on goLive/endStream/stopSession; returns the new
    /// generation so the engine can filter stale connection signals.
    func bumpGeneration() -> Int {
        generation.withLock { value in
            value += 1
            return value
        }
    }

    private func yield(_ signal: EngineSignal) {
        signals.yield(StampedSignal(generation: generation.withLock { $0 }, signal: signal))
    }

    func mediaOnSrtConnected() {
        yield(.connected)
    }

    func mediaOnSrtDisconnected(_ reason: String) {
        yield(.disconnected(reason: reason))
    }

    func mediaOnRtmpConnected() {
        yield(.connected)
    }

    func mediaOnRtmpDisconnected(_ message: String) {
        yield(.disconnected(reason: message))
    }

    func mediaOnRtmpDestinationConnected(_: String) {}

    func mediaOnRtmpDestinationDisconnected(_: String) {}

    func mediaOnRistConnected() {
        yield(.connected)
    }

    func mediaOnRistDisconnected() {
        yield(.disconnected(reason: ""))
    }

    func mediaOnWhipConnected() {
        yield(.connected)
    }

    func mediaOnWhipDisconnected(_ reason: String) {
        yield(.disconnected(reason: reason))
    }

    func mediaOnWhipPerform(request: URLRequest,
                            queue _: DispatchQueue,
                            completion: (@MainActor (Data?, URLResponse?, (any Error)?) -> Void)?) {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            Task { @MainActor in
                completion?(data, response, error)
            }
        }
        task.resume()
    }

    func mediaOnAudioMuteChange() {
        yield(.audioMuteChanged)
    }

    func mediaOnAudioBuffer(_: CMSampleBuffer) {}

    func mediaOnLowFpsImage(_: Data?, _: UInt64) {}

    func mediaOnAttachCameraError() {
        yield(.attachCameraError)
    }

    func mediaOnCaptureSessionError(_ message: String) {
        yield(.captureSessionError(message))
    }

    func mediaOnBufferedVideoReady(cameraId _: UUID) {}

    func mediaOnBufferedVideoRemoved(cameraId _: UUID) {}

    func mediaOnEncoderResolutionChanged(resolution: CGSize) {
        yield(.encoderResolutionChanged(resolution))
    }

    func mediaOnRecorderInitSegment(data _: Data) {}

    func mediaOnRecorderDataSegment(segment _: RecorderDataSegment) {}

    func mediaOnRecorderFinished() {}

    func mediaOnNoTorch() {}

    func mediaOnFps(fps: Int) {
        yield(.fps(fps))
    }

    func mediaStrlaRelayDestinationAddress(address _: String, port _: UInt16) {}

    func mediaSetZoomX(x _: Float) {}

    func mediaSetExposureBias(bias _: Float) {}

    func mediaSelectedFps(auto _: Bool) {}

    func mediaError(error: any Error) {
        yield(.mediaError(error.localizedDescription))
    }
}
