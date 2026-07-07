import Testing
import Foundation
@testable import IRLTPBonding

/// Live integration test for the Swift transport against the real Rust receiver.
///
/// Opt-in (needs a host-run `irltp-receiver` on 127.0.0.1:5000); the harness
/// `testbed`-style script sets IRLTP_LIVE=1 and starts the receiver + a sink.
/// Proves the NWConnection transport drives the sans-IO session through the full
/// SRTLA registration handshake over real sockets and streams data across the
/// bond.
struct IRLTPBondingClientLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IRLTP_LIVE"] == "1"))
    func registersAndStreamsAgainstRealReceiver() {
        let client = IRLTPBondingClient(
            receiverHost: "127.0.0.1",
            receiverPort: 5000,
            links: [.init(), .init()] // two loopback links (no interface pinning)
        )
        let established = DispatchSemaphore(value: 0)
        client.onSessionEstablished = { established.signal() }
        client.start()

        // The full probe -> REG1 -> REG2 -> REG3 handshake must complete over
        // real UDP sockets against the receiver.
        let ok = established.wait(timeout: .now() + 12) == .success
        #expect(ok, "bond must register against a live irltp-receiver on :5000")

        if ok {
            // Stream ~600 synthetic SRT-data packets across the bond; the
            // harness verifies they reach the receiver's SRT egress.
            var seq: UInt32 = 0
            for _ in 0..<600 {
                client.sendLocalSRT(makeSrtDataPacket(seq: &seq))
                usleep(1_500) // ~650 pps
            }
            Thread.sleep(forTimeInterval: 1.0) // drain
        }
        client.stop()
    }

    /// A minimal SRT-data-shaped datagram: high bit of byte 0 clear marks it as
    /// SRT data (not SRTLA control), with a 31-bit sequence number up front.
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
