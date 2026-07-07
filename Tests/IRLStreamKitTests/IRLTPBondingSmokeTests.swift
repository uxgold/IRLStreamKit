import Testing
@testable import IRLTPBonding

/// Proves the cross-compiled IRLTP Rust core links and executes in-process:
/// the sans-IO sender must run its bootstrap and emit registration sends.
struct IRLTPBondingSmokeTests {
    @Test func coreRunsAndEmitsBootstrapSends() {
        let result = IRLTPBondingSmoke.run()
        // Two links coming up must produce at least the registration probes.
        #expect(result.bootstrapActions > 0)
        #expect(result.sendActions >= 2)
        // A fresh link starts at the default window (20 * 1000 milli-packets).
        #expect(result.link0Window == 20_000)
    }
}
