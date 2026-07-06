// Resolves capture devices from the public CameraSelection and builds the
// vendored VideoUnitAttachParams (pinning Moblin-app-only knobs to upstream
// defaults, each noted with its origin).

import AVFoundation
import Foundation

@MainActor
final class CameraController {
    // Stable per-device UUIDs — mirrors Model.builtinCameraIds.
    private var builtinCameraIds: [String: UUID] = [:]
    // Required by VideoUnitAttachParams; only used when showCameraPreview is
    // true, which the facade pins to false (the drawable preview is used).
    let cameraPreviewLayer = AVCaptureVideoPreviewLayer()

    static func requestPermissions() async -> StreamEngineError? {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            return .cameraPermissionDenied
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return .microphonePermissionDenied
        }
        return nil
    }

    func device(for selection: CameraSelection) -> AVCaptureDevice? {
        switch selection {
        case .back:
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .front:
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    func cameraId(for device: AVCaptureDevice) -> UUID {
        if let id = builtinCameraIds[device.uniqueID] {
            return id
        }
        let id = UUID()
        builtinCameraIds[device.uniqueID] = id
        return id
    }

    func attachParams(device: AVCaptureDevice) -> VideoUnitAttachParams {
        VideoUnitAttachParams(
            devices: CaptureDevices(hasSceneDevice: true,
                                    devices: [CaptureDevice(device: device,
                                                            id: cameraId(for: device),
                                                            isVideoMirrored: false)]),
            builtinDelay: 0, // upstream: database.debug.builtinAudioAndVideoDelay default
            cameraPreviewLayer: cameraPreviewLayer,
            showCameraPreview: false, // facade uses the processed drawable preview
            externalDisplayPreview: false,
            bufferedVideo: nil,
            preferredVideoStabilizationMode: .off, // upstream scene default
            ignoreFramesAfterAttachSeconds: 0.0,
            fillFrame: false,
            isLandscapeStreamAndPortraitUi: false,
            forceSceneTransition: false,
            macScreenCapture: false
        )
    }

    func detachParams() -> VideoUnitAttachParams {
        // Mirrors Model.detachCamera: empty devices tears down capture.
        VideoUnitAttachParams(
            devices: CaptureDevices(hasSceneDevice: false, devices: []),
            builtinDelay: 0,
            cameraPreviewLayer: cameraPreviewLayer,
            showCameraPreview: false,
            externalDisplayPreview: false,
            bufferedVideo: nil,
            preferredVideoStabilizationMode: .off,
            ignoreFramesAfterAttachSeconds: 0.0,
            fillFrame: false,
            isLandscapeStreamAndPortraitUi: false,
            forceSceneTransition: false,
            macScreenCapture: false
        )
    }
}
