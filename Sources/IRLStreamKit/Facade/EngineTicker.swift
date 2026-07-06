// Owns engine timing so consumers never do. Cadences mirror Moblin's Model
// timers: 20 ms adaptive-bitrate tick (Media counts ticks internally — a
// wrong cadence silently degrades BELABOX ABR), 200 ms audio level, 1 s
// transport/bonding stats.

import Foundation

@MainActor
final class EngineTicker {
    private var abrTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?

    var onAbrTick: (() -> Void)?
    var onAudioTick: (() -> Void)?
    var onStatsTick: (() -> Void)?

    func start() {
        stop()
        abrTask = makeLoop(milliseconds: 20) { [weak self] in self?.onAbrTick?() }
        audioTask = makeLoop(milliseconds: 200) { [weak self] in self?.onAudioTick?() }
        statsTask = makeLoop(milliseconds: 1000) { [weak self] in self?.onStatsTick?() }
    }

    func stop() {
        abrTask?.cancel()
        audioTask?.cancel()
        statsTask?.cancel()
        abrTask = nil
        audioTask = nil
        statsTask = nil
    }

    private func makeLoop(milliseconds: Int, _ tick: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(milliseconds))
                } catch {
                    return
                }
                tick()
            }
        }
    }
}
