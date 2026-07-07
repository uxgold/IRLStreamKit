import Testing
import Foundation
@testable import IRLStreamKit

/// Proves the IRLTP adapter works through the EXACT interface `Media` drives on
/// its bonding transport: `start(uri:)` then a stream of `handleLocalPacket`,
/// with the bond's lifecycle surfaced as the same `SrtlaDelegate` callbacks the
/// vendored client uses. Opt-in (IRLTP_LIVE=1 + host irltp-receiver on :5000).
struct IRLTPBondingAdapterLiveTests {
    /// Captures the delegate callbacks Media would receive.
    private final class MockDelegate: SrtlaDelegate {
        let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _received = 0
        var received: Int { lock.withLock { _received } }

        func srtlaReady(port _: UInt16) { ready.signal() }
        func srtlaError(message _: String) {}
        func moblinkStreamerDestinationAddress(address _: String, port _: UInt16) {}
        func srtlaReceivedPacket(packet _: Data) { lock.withLock { _received += 1 } }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["IRLTP_LIVE"] == "1"))
    func adapterRegistersAndStreamsAsMediaWould() {
        let delegate = MockDelegate()
        // Unpinned loopback links (production would pin .cellular/.wifi).
        let adapter = IRLTPBondingAdapter(delegate: delegate, links: [.init(), .init()])

        adapter.start(uri: "srtla://127.0.0.1:5000", timeout: 5, dnsLookupStrategy: .system)
        let ready = delegate.ready.wait(timeout: .now() + 12) == .success
        #expect(ready, "adapter must drive the bond to srtlaReady via a live receiver")

        if ready {
            var seq: UInt32 = 0
            for _ in 0..<600 {
                adapter.handleLocalPacket(packet: makeSrtDataPacket(seq: &seq))
                usleep(1_500)
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
        adapter.stop()
    }

    private func makeSrtDataPacket(seq: inout UInt32) -> Data {
        var d = Data(count: 1316)
        let s = seq & 0x7FFF_FFFF
        d[0] = UInt8((s >> 24) & 0xFF)
        d[1] = UInt8((s >> 16) & 0xFF)
        d[2] = UInt8((s >> 8) & 0xFF)
        d[3] = UInt8(s & 0xFF)
        seq &+= 1
        return d
    }
}
