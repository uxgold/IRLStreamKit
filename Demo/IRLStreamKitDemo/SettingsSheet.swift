import IRLStreamKit
import SwiftUI

struct SettingsSheet: View {
    @Binding var settings: DemoSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Endpoint") {
                    Picker("Protocol", selection: $settings.endpointKind) {
                        Text("SRTLA (bonded)").tag(DemoSettings.EndpointKind.srtla)
                        Text("SRT").tag(DemoSettings.EndpointKind.srt)
                        Text("RTMP").tag(DemoSettings.EndpointKind.rtmp)
                    }
                    TextField("URL", text: $settings.urlString, prompt: Text(urlPrompt))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                if settings.endpointKind != .rtmp {
                    Section("SRT") {
                        Stepper(
                            "Latency: \(settings.latencyMilliseconds) ms",
                            value: $settings.latencyMilliseconds,
                            in: 500 ... 8000,
                            step: 250
                        )
                        Stepper(
                            String(format: "Reconnect delay: %.0f s", settings.reconnectDelaySeconds),
                            value: $settings.reconnectDelaySeconds,
                            in: 1 ... 30,
                            step: 1
                        )
                        Picker("Adaptive bitrate", selection: adaptiveBitrateBinding) {
                            ForEach(AdaptiveBitratePreset.allCases, id: \.rawValue) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                    }
                }
                if settings.endpointKind == .srtla {
                    Section("Bonding") {
                        Picker("Implementation", selection: bondingImplementationBinding) {
                            Text("Moblin SRTLA").tag(BondingImplementation.moblinSRTLA)
                            Text("IRLTP (Rust)").tag(BondingImplementation.irltp)
                        }
                        .pickerStyle(.segmented)
                        Toggle("Manual priorities", isOn: $settings.manualBondingPriorities)
                        if settings.manualBondingPriorities {
                            ForEach($settings.bondingLinks) { $link in
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle(link.interfaceRaw.capitalized, isOn: $link.enabled)
                                    if link.enabled {
                                        Stepper(
                                            "Priority: \(link.priority)",
                                            value: $link.priority,
                                            in: 1 ... 10
                                        )
                                        .font(.callout)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Video") {
                    Picker("Resolution", selection: resolutionBinding) {
                        ForEach(StreamResolution.allCases, id: \.rawValue) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }
                    Picker("Frame rate", selection: $settings.frameRate) {
                        ForEach([24, 25, 30, 50, 60], id: \.self) { fps in
                            Text("\(fps)").tag(fps)
                        }
                    }
                    Picker("Codec", selection: codecBinding) {
                        Text("HEVC").tag(StreamCodec.hevc)
                        Text("H.264").tag(StreamCodec.h264)
                    }
                    Toggle("Portrait stream", isOn: $settings.isPortrait)
                }
                Section("Audio") {
                    Picker("Bitrate", selection: $settings.audioBitrateKilobits) {
                        ForEach([64, 96, 128, 160, 192, 256, 320], id: \.self) { kbps in
                            Text("\(kbps) kb/s").tag(kbps)
                        }
                    }
                }
            }
            .navigationTitle("Stream settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var urlPrompt: String {
        switch settings.endpointKind {
        case .srtla: "srtla://host:port?streamid=…"
        case .srt: "srt://host:port?streamid=…"
        case .rtmp: "rtmp://host/app/streamkey"
        }
    }

    private var adaptiveBitrateBinding: Binding<AdaptiveBitratePreset> {
        Binding(get: { settings.adaptiveBitrate }, set: { settings.adaptiveBitrate = $0 })
    }

    private var bondingImplementationBinding: Binding<BondingImplementation> {
        Binding(get: { settings.bondingImplementation }, set: { settings.bondingImplementation = $0 })
    }

    private var resolutionBinding: Binding<StreamResolution> {
        Binding(get: { settings.resolution }, set: { settings.resolution = $0 })
    }

    private var codecBinding: Binding<StreamCodec> {
        Binding(get: { settings.codec }, set: { settings.codec = $0 })
    }
}
