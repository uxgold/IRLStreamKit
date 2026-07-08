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

    // Official libsrt mode: the SRT engine is libsrt (SrtStreamOfficial), which
    // sends via a callback -> handleLocalPacket -> bond, and RECEIVES on a real
    // socket connected to a localhost listener we own. We route bond-inbound to
    // that listener (-> libsrt), exactly as SrtlaClient does in official mode.
    // srtlaReady must fire only once BOTH the bond has registered and the local
    // listener is up. (Accessed on srtlaClientQueue.)
    private var localListener: LocalListener?
    private var bondReady = false
    private var listenerPort: UInt16?

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
        client.onSessionEstablished = { [weak self] in
            srtlaClientQueue.async { self?.bondReady = true; self?.maybeFireReady() }
        }
        client.onForwardToLocalSrt = { [weak self] data in
            guard let self else { return }
            self.diagQueue.async { self.inCounts[Self.srtKind(data), default: 0] += 1 }
            // Official mode: hand inbound SRT to libsrt via the local listener.
            srtlaClientQueue.async { self.localListener?.sendPacket(packet: data) }
        }

        let listener = LocalListener()
        listener.onReady = { [weak self] port in
            srtlaClientQueue.async { self?.listenerPort = port; self?.maybeFireReady() }
        }
        listener.onError = { [weak self] message in
            self?.delegate?.srtlaError(message: "IRLTP local listener: \(message)")
        }

        self.client = client
        self.localListener = listener
        listener.start()
        client.start()
        startDiag()
    }

    /// Fire srtlaReady once the bond has registered AND the local listener is up,
    /// giving Media the port libsrt should connect to. (On srtlaClientQueue.)
    private func maybeFireReady() {
        guard !readyFired, bondReady, let port = listenerPort else { return }
        readyFired = true
        delegate?.srtlaReady(port: port)
    }

    func stop() {
        diagTimer?.cancel(); diagTimer = nil
        client?.stop()
        client = nil
        localListener?.stop()
        localListener = nil
        readyFired = false
        bondReady = false
        listenerPort = nil
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
