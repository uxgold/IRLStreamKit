// The single churn-absorber for upstream's MediaDelegate. Media fires these
// callbacks from its processing/network queues; the adapter funnels the ones
// the facade cares about into ONE AsyncStream consumed by a single MainActor
// task in IRLStreamEngine (preserving ordering across the queue hop). When a
// Moblin sync adds/renames a MediaDelegate method, THIS file fails to compile
// — the public surface never moves.

import CoreMedia
import Foundation

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

final class MediaDelegateAdapter: MediaDelegate {
    private let signals: AsyncStream<EngineSignal>.Continuation

    init(signals: AsyncStream<EngineSignal>.Continuation) {
        self.signals = signals
    }

    func mediaOnSrtConnected() {
        signals.yield(.connected)
    }

    func mediaOnSrtDisconnected(_ reason: String) {
        signals.yield(.disconnected(reason: reason))
    }

    func mediaOnRtmpConnected() {
        signals.yield(.connected)
    }

    func mediaOnRtmpDisconnected(_ message: String) {
        signals.yield(.disconnected(reason: message))
    }

    func mediaOnRtmpDestinationConnected(_: String) {}

    func mediaOnRtmpDestinationDisconnected(_: String) {}

    func mediaOnRistConnected() {
        signals.yield(.connected)
    }

    func mediaOnRistDisconnected() {
        signals.yield(.disconnected(reason: ""))
    }

    func mediaOnWhipConnected() {
        signals.yield(.connected)
    }

    func mediaOnWhipDisconnected(_ reason: String) {
        signals.yield(.disconnected(reason: reason))
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
        signals.yield(.audioMuteChanged)
    }

    func mediaOnAudioBuffer(_: CMSampleBuffer) {}

    func mediaOnLowFpsImage(_: Data?, _: UInt64) {}

    func mediaOnAttachCameraError() {
        signals.yield(.attachCameraError)
    }

    func mediaOnCaptureSessionError(_ message: String) {
        signals.yield(.captureSessionError(message))
    }

    func mediaOnBufferedVideoReady(cameraId _: UUID) {}

    func mediaOnBufferedVideoRemoved(cameraId _: UUID) {}

    func mediaOnEncoderResolutionChanged(resolution: CGSize) {
        signals.yield(.encoderResolutionChanged(resolution))
    }

    func mediaOnRecorderInitSegment(data _: Data) {}

    func mediaOnRecorderDataSegment(segment _: RecorderDataSegment) {}

    func mediaOnRecorderFinished() {}

    func mediaOnNoTorch() {}

    func mediaOnFps(fps: Int) {
        signals.yield(.fps(fps))
    }

    func mediaStrlaRelayDestinationAddress(address _: String, port _: UInt16) {}

    func mediaSetZoomX(x _: Float) {}

    func mediaSetExposureBias(bias _: Float) {}

    func mediaSelectedFps(auto _: Bool) {}

    func mediaError(error: any Error) {
        signals.yield(.mediaError(error.localizedDescription))
    }
}
