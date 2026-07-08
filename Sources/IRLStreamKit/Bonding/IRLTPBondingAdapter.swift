import Foundation
import Network
import IRLTPBonding
import os

/// Drop-in ``LocalSrtBonding`` backed by the IRLTP Rust core: it presents the
/// exact interface `Media` drives on `SrtlaClient`, but the SRTLA protocol runs
/// in the sans-IO Rust sender behind ``IRLTPBondingClient``.
///
/// `Media` produces SRT packets and calls `handleLocalPacket`; we bond them out.
/// The bond's replies and registration come back as the same `SrtlaDelegate`
/// callbacks the vendored client uses — `srtlaReceivedPacket` and `srtlaReady` —
/// so the SRT engine's lifecycle (which opens on `srtlaReady`) is unchanged.
final class IRLTPBondingAdapter: LocalSrtBonding {
    private weak var delegate: (any SrtlaDelegate)?
    private let links: [IRLTPBondingClient.Link]
    private var client: IRLTPBondingClient?
    private var readyFired = false

    // Diagnostics: SRT packet flow at the adapter boundary.
    private let log = Logger(subsystem: "com.uxirl.irltp", category: "adapter")
    private let diagQueue = DispatchQueue(label: "irltp.adapter.diag")
    private var diagTimer: DispatchSourceTimer?
    private var outCounts = [String: Int]()
    private var inCounts = [String: Int]()

    /// Classify an SRT packet: "data", or a control subtype (hs/ka/ack/nak/...).
    private static func srtKind(_ d: Data) -> String {
        guard let b0 = d.first else { return "empty" }
        if b0 & 0x80 == 0 { return "data" }
        guard d.count >= 2 else { return "ctrl?" }
        let t = (UInt16(b0) << 8 | UInt16(d[d.index(after: d.startIndex)])) & 0x7FFF
        switch t {
        case 0x0000: return "hs"       // handshake
        case 0x0001: return "ka"       // keepalive
        case 0x0002: return "ack"
        case 0x0003: return "nak"
        case 0x0005: return "shutdown"
        case 0x0006: return "ackack"
        default: return "ctrl\(t)"
        }
    }

    /// - Parameter links: one entry per bonded path. Production pins to
    ///   interface types (e.g. `.cellular`, `.wifi`); tests pass unpinned links.
    init(delegate: any SrtlaDelegate, links: [IRLTPBondingClient.Link]) {
        self.delegate = delegate
        self.links = links
    }

    func start(uri: String, timeout _: Double, dnsLookupStrategy _: SettingsDnsLookupStrategy) {
        guard let url = URL(string: uri), let host = url.host, let port = url.port,
              let port16 = UInt16(exactly: port)
        else {
            delegate?.srtlaError(message: "IRLTP: malformed URL \(uri)")
            return
        }
        let client = IRLTPBondingClient(receiverHost: host, receiverPort: port16, links: links)
        // CRITICAL: the delegate callbacks feed Moblin's SRT engine
        // (srtlaReceivedPacket -> SrtSender.input). Moblin drives that engine's
        // output on srtlaClientQueue, so its input MUST land on the same queue —
        // otherwise SrtSender.input races SrtSender.enqueue and the SRT handshake
        // never completes (frames encode but nothing ships). Match Moblin's
        // contract by hopping onto srtlaClientQueue, exactly as SrtlaClient does.
        client.onSessionEstablished = { [weak self] in
            guard let self, !self.readyFired else { return }
            self.readyFired = true
            srtlaClientQueue.async { self.delegate?.srtlaReady(port: 0) }
        }
        client.onForwardToLocalSrt = { [weak self] data in
            guard let self else { return }
            self.diagQueue.async { self.inCounts[Self.srtKind(data), default: 0] += 1 }
            srtlaClientQueue.async { self.delegate?.srtlaReceivedPacket(packet: data) }
        }
        self.client = client
        client.start()
        startDiag()
    }

    func stop() {
        diagTimer?.cancel(); diagTimer = nil
        client?.stop()
        client = nil
        readyFired = false
    }

    func handleLocalPacket(packet: Data) {
        diagQueue.async { self.outCounts[Self.srtKind(packet), default: 0] += 1 }
        client?.sendLocalSRT(packet)
    }

    private func startDiag() {
        let t = DispatchSource.makeTimerSource(queue: diagQueue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let out = self.outCounts.sorted { $0.key < $1.key }.map { "\($0)=\($1)" }.joined(separator: ",")
            let inn = self.inCounts.sorted { $0.key < $1.key }.map { "\($0)=\($1)" }.joined(separator: ",")
            self.log.notice("SRT out[\(out, privacy: .public)] in[\(inn, privacy: .public)]")
            self.outCounts.removeAll(); self.inCounts.removeAll()
        }
        t.resume()
        diagTimer = t
    }

    func connectionStatistics() -> [BondingConnection] {
        guard let client else { return [] }
        return client.snapshot().enumerated().compactMap { i, s -> BondingConnection? in
            guard s.registered else { return nil }
            return BondingConnection(
                name: s.interfaceType.map(Self.name(for:)) ?? "link\(i)",
                usage: s.txBytes,
                rtt: s.rttMs.map { Int($0) }
            )
        }
    }

    func logStatistics() {}
    func getTotalByteCount() -> Int64 { 0 }
    func setConnectionPriorities(connectionPriorities _: SettingsStreamSrtConnectionPriorities) {}
    func setNetworkInterfaceNames(networkInterfaceNames _: [SettingsNetworkInterfaceName]) {}
    func addMoblink(endpoint _: NWEndpoint, id _: UUID, name _: String) {}
    func removeMoblink(endpoint _: NWEndpoint) {}

    private static func name(for type: NWInterface.InterfaceType) -> String {
        switch type {
        case .cellular: return "Cellular"
        case .wifi: return "WiFi"
        case .wiredEthernet: return "Ethernet"
        default: return "Other"
        }
    }
}
