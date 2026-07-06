import Foundation

/// Multi-subscriber AsyncStream fan-out. Each events() call gets its own
/// continuation; termination removes it.
@MainActor
package final class EventBroadcaster {
    private var continuations: [UUID: AsyncStream<StreamEvent>.Continuation] = [:]

    package init() {}

    package func subscribe() -> AsyncStream<StreamEvent> {
        // Bounded: a subscriber that stops consuming drops its oldest events
        // instead of growing memory for the whole stream duration. Events are
        // notifications, not the source of truth — `state` is.
        AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
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
