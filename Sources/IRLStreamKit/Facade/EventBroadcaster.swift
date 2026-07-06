import Foundation

/// Multi-subscriber AsyncStream fan-out. Each events() call gets its own
/// continuation; termination removes it.
@MainActor
package final class EventBroadcaster {
    private var continuations: [UUID: AsyncStream<StreamEvent>.Continuation] = [:]

    package init() {}

    package func subscribe() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor in
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    package func yield(_ event: StreamEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    package func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
