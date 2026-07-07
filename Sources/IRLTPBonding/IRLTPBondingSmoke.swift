import Foundation

/// Minimal in-process exercise of the IRLTP Rust core, to prove the
/// cross-compiled sans-IO sender links and runs inside an iOS process.
///
/// This drives the bootstrap of a 2-link sender and inspects what the state
/// machine emits — no sockets involved, exactly as the architecture intends
/// (Swift owns the transport; Rust is the protocol).
public enum IRLTPBondingSmoke {
    public struct Result {
        public let bootstrapActions: Int
        public let sendActions: Int
        public let link0Window: Int64
        public let summary: String
    }

    public static func run() -> Result {
        let sender = IrltpSender(linkCount: 2)

        // Both links come up during bootstrap; the sans-IO core should emit
        // registration probes (Send actions) it wants the caller to transmit.
        var actions: [IrltpAction] = []
        actions += sender.linkReady(link: 0, nowMs: 0)
        actions += sender.linkReady(link: 1, nowMs: 0)
        actions += sender.tick(nowMs: 10)

        let sends = actions.reduce(into: 0) { count, action in
            if case .send = action { count += 1 }
        }
        let stats0 = sender.linkStats(link: 0)

        let summary = "IRLTP core alive — \(actions.count) bootstrap actions "
            + "(\(sends) sends), link0 window=\(stats0.window)"
        return Result(
            bootstrapActions: actions.count,
            sendActions: sends,
            link0Window: stats0.window,
            summary: summary
        )
    }
}
