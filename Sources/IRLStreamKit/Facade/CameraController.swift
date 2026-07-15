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
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            // Center Stage is a front-camera feature; keep it off for the rear
            // sensor so it doesn't constrain the rear format set.
            setCenterStage(enabled: false, for: device)
            return device
        case .front:
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            // Auto-frame the subject on the front ultra-wide sensor.
            setCenterStage(enabled: true, for: device)
            return device
        }
    }

    /// Center Stage is process-wide (class properties), not per-device, and
    /// "supported" is a per-*format* property — there's no device-level flag.
    /// Two rules make it crash-safe:
    ///   1. Set `centerStageControlMode` before toggling enablement (so the app,
    ///      not Control Center, owns it).
    ///   2. Enabling while the device's *active* format doesn't support Center
    ///      Stage raises an uncatchable NSException — so only enable when the
    ///      current active format already supports it. `VideoUnit.findVideoFormat`
    ///      then keeps the engine on a Center-Stage-capable format for the later
    ///      `activeFormat` swap, and disables Center Stage instead of crashing if
    ///      no matching format supports it.
    private func setCenterStage(enabled: Bool, for device: AVCaptureDevice?) {
        AVCaptureDevice.centerStageControlMode = .app
        guard enabled else {
            AVCaptureDevice.isCenterStageEnabled = false
            return
        }
        guard let device, device.activeFormat.isCenterStageSupported else { return }
        AVCaptureDevice.isCenterStageEnabled = true
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
                                    devices: [CaptureDevice(
                                        device: device,
                                        id: cameraId(for: device),
                                        // upstream: mirrorFrontCameraOnStream default true
                                        isVideoMirrored: device.position == .front
                                    )]),
            builtinDelay: 0, // upstream: database.debug.builtinAudioAndVideoDelay default
            cameraPreviewLayer: cameraPreviewLayer,
            showCameraPreview: false, // facade uses the processed drawable preview
            externalDisplayPreview: false,
            bufferedVideo: nil,
            preferredVideoStabilizationMode: .off, // upstream scene default
            ignoreFramesAfterAttachSeconds: 0.3, // upstream: cameraSwitchRemoveBlackish default
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
