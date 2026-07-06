// App-side model. Consumes IRLStreamKit strictly through its public API —
// this file (and the whole demo app) is the reference for how UX IRL will
// integrate the library.

import Foundation
import IRLStreamKit
import Observation
import UIKit

@MainActor
@Observable
final class DemoModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    let engine = IRLStreamEngine()
    private(set) var log: [LogEntry] = []
    var lastError: String?

    var settings = DemoSettings.load() {
        didSet {
            settings.save()
        }
    }

    // Ends on its own: when the model (and thus the engine) goes away, the
    // engine finishes its event streams and the for-await loop exits.
    private var eventsTask: Task<Void, Never>?

    init() {
        let events = engine.events()
        eventsTask = Task { [weak self] in
            for await event in events {
                self?.append(event)
            }
        }
    }

    var state: StreamEngineState {
        engine.state
    }

    // MARK: - Actions

    func toggleSession() {
        if case .idle = state.phase {
            Task {
                do {
                    try await engine.startSession(camera: state.camera)
                } catch {
                    report(error)
                }
            }
        } else {
            engine.stopSession()
        }
    }

    func toggleStream() {
        if state.phase.isLive || state.phase == .connecting {
            engine.endStream()
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        guard let configuration = settings.buildConfiguration() else {
            lastError = "Invalid endpoint URL: \(settings.urlString)"
            appendText("config rejected: invalid URL")
            return
        }
        Task {
            do {
                try await engine.goLive(configuration)
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                report(error)
            }
        }
    }

    func flipCamera() {
        engine.setCamera(state.camera == .back ? .front : .back)
    }

    func toggleMute() {
        engine.setMicMuted(!state.isMicMuted)
    }

    func setTargetBitrate(megabits: Double) {
        engine.setTargetBitrate(Int(megabits * 1_000_000))
    }

    // MARK: - Log

    private func report(_ error: Error) {
        let text = describe(error)
        lastError = text
        appendText("error: \(text)")
    }

    private func append(_ event: StreamEvent) {
        appendText(describe(event))
    }

    private func appendText(_ text: String) {
        log.append(LogEntry(date: Date(), text: text))
        if log.count > 500 {
            log.removeFirst(log.count - 500)
        }
    }

    private func describe(_ event: StreamEvent) -> String {
        switch event {
        case let .phaseChanged(phase):
            "phase → \(phase.label)"
        case let .statsUpdated(stats):
            "stats: cur \(stats.currentBitrate.bitrateLabel) tport \(stats.transportBitrate.bitrateLabel) fps \(stats.encoderFps)"
        case let .bondingUpdated(links):
            "bonding: " + links.map { "\($0.name) \(Int($0.shareOfTotal * 100))%" }.joined(separator: ", ")
        case let .audioLevelUpdated(level):
            level.decibels.map { String(format: "audio %.0f dB", $0) } ?? "audio muted"
        case let .micMuteChanged(isMuted):
            isMuted ? "mic muted" : "mic unmuted"
        case let .cameraChanged(camera):
            "camera → \(camera.rawValue)"
        case let .adaptiveBitrateChanged(bitsPerSecond):
            "abr → \(bitsPerSecond.bitrateLabel)"
        case let .encoderResolutionChanged(width, height):
            "encoder resolution → \(width)x\(height)"
        case .cameraAttachFailed:
            "camera attach FAILED"
        case let .failed(error):
            "failed: \(describe(error))"
        @unknown default:
            "unknown event"
        }
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? StreamEngineError {
            switch error {
            case .cameraPermissionDenied: return "camera permission denied"
            case .microphonePermissionDenied: return "microphone permission denied"
            case .cameraUnavailable: return "camera unavailable"
            case let .captureSessionFailed(message): return "capture session failed: \(message)"
            case .notInSession: return "not in session — start the camera first"
            case .alreadyLive: return "already live"
            case let .invalidConfiguration(reason): return "invalid configuration: \(reason)"
            case let .connectionFailed(message): return "connection failed: \(message)"
            }
        }
        return error.localizedDescription
    }
}

extension StreamPhase {
    var label: String {
        switch self {
        case .idle: "idle"
        case .previewing: "preview"
        case .connecting: "connecting"
        case .live: "LIVE"
        case let .reconnecting(reason): reason.isEmpty ? "reconnecting" : "reconnecting (\(reason))"
        }
    }
}

extension Int {
    var bitrateLabel: String {
        if self >= 1_000_000 {
            String(format: "%.1f Mb/s", Double(self) / 1_000_000)
        } else {
            String(format: "%d kb/s", self / 1000)
        }
    }
}
