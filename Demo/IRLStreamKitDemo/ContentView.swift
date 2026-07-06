import IRLStreamKit
import SwiftUI

private let accent = Color(red: 0x50 / 255, green: 0xF2 / 255, blue: 0x62 / 255)

struct ContentView: View {
    @Bindable var model: DemoModel
    @State private var showSettings = false
    @State private var showLog = false

    var body: some View {
        ZStack {
            if case .idle = model.state.phase {
                idlePlaceholder
            } else {
                CameraPreviewView(source: model.engine)
                    .ignoresSafeArea()
            }
            VStack(spacing: 8) {
                topBar
                statsBar
                if !model.state.bondingLinks.isEmpty {
                    BondingBar(links: model.state.bondingLinks)
                }
                Spacer()
                AudioMeter(level: model.state.audioLevel)
                bitrateSlider
                controls
            }
            .padding(.horizontal, 12)
        }
        .background(Color(red: 0x0B / 255, green: 0x0C / 255, blue: 0x0B / 255))
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: $model.settings)
        }
        .sheet(isPresented: $showLog) {
            EventLogSheet(entries: model.log)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Camera off")
                .foregroundStyle(.secondary)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            PhaseChip(phase: model.state.phase)
            UptimeLabel(phase: model.state.phase)
            Spacer()
            Button {
                showLog = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .disabled(model.state.phase.isLive || model.state.phase == .connecting)
        }
        .padding(.top, 4)
    }

    private var statsBar: some View {
        HStack(spacing: 14) {
            StatLabel(title: "cur", value: model.state.stats.currentBitrate.bitrateLabel)
            StatLabel(title: "tport", value: model.state.stats.transportBitrate.bitrateLabel)
            StatLabel(title: "fps", value: "\(model.state.stats.encoderFps)")
            StatLabel(title: "sent", value: byteLabel(model.state.stats.totalBytesSent))
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var bitrateSlider: some View {
        HStack {
            Text("target")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { model.settings.targetBitrateMegabits },
                    set: { newValue in
                        model.settings.targetBitrateMegabits = newValue
                        if model.state.phase.isLive {
                            model.setTargetBitrate(megabits: newValue)
                        }
                    }
                ),
                in: 0.5 ... 12,
                step: 0.5
            )
            .tint(accent)
            Text(String(format: "%.1f Mb/s", model.settings.targetBitrateMegabits))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: model.toggleMute) {
                Image(systemName: model.state.isMicMuted ? "mic.slash.fill" : "mic.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(model.state.isMicMuted ? .red : .primary)

            Button(action: model.flipCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isIdle)

            Button(action: model.toggleStream) {
                Text(streamButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.state.phase.isLive || model.state.phase == .connecting ? .red : accent)
            .foregroundStyle(.black)
            .disabled(isIdle)

            Button(action: model.toggleSession) {
                Image(systemName: isIdle ? "video.fill" : "video.slash.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(model.state.phase.isLive)
        }
        .padding(.bottom, 8)
    }

    private var isIdle: Bool {
        if case .idle = model.state.phase { true } else { false }
    }

    private var streamButtonTitle: String {
        switch model.state.phase {
        case .idle, .previewing: "GO LIVE"
        case .connecting: "CANCEL"
        case .live, .reconnecting: "END"
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}

struct PhaseChip: View {
    let phase: StreamPhase

    var body: some View {
        Text(phase.label)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch phase {
        case .idle: .gray.opacity(0.4)
        case .previewing: .black.opacity(0.6)
        case .connecting: .orange
        case .live: .red
        case .reconnecting: .orange
        }
    }

    private var foreground: Color {
        switch phase {
        case .previewing, .idle: .white
        default: .black
        }
    }
}

struct UptimeLabel: View {
    let phase: StreamPhase

    var body: some View {
        if case let .live(since) = phase {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(uptime(since: since, now: context.date))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
    }

    private func uptime(since: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(since)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.white)
        }
    }
}

struct BondingBar: View {
    let links: [BondingLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(links) { link in
                HStack(spacing: 6) {
                    Text(link.name)
                        .frame(width: 64, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent)
                                .frame(width: proxy.size.width * link.shareOfTotal)
                        }
                    }
                    .frame(height: 6)
                    Text(link.rttMilliseconds.map { "\($0) ms" } ?? "—")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AudioMeter: View {
    let level: AudioLevel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: level.decibels == nil ? "mic.slash" : "waveform")
                .font(.caption2)
                .foregroundStyle(level.decibels == nil ? .red : .secondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(meterColor)
                        .frame(width: proxy.size.width * normalizedLevel)
                }
            }
            .frame(height: 6)
            Text(level.decibels.map { String(format: "%.0f dB", $0) } ?? "muted")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    // Audio level arrives in dBFS (negative, 0 == clipping).
    private var normalizedLevel: Double {
        guard let decibels = level.decibels else {
            return 0
        }
        return Double(min(max((decibels + 60) / 60, 0), 1))
    }

    private var meterColor: Color {
        guard let decibels = level.decibels else {
            return .red
        }
        return decibels > -8 ? .red : accent
    }
}
