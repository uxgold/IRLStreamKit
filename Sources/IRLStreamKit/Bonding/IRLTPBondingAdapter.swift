import Foundation
import Network
import IRLTPBonding

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
            guard let self, !self.readyFired else { return }
            self.readyFired = true
            // Mirror SrtlaClient: signal the SRT engine to open. port 0 = the
            // Moblin (direct-delegate) path; the engine does not bind a socket.
            self.delegate?.srtlaReady(port: 0)
        }
        client.onForwardToLocalSrt = { [weak self] data in
            self?.delegate?.srtlaReceivedPacket(packet: data)
        }
        self.client = client
        client.start()
    }

    func stop() {
        client?.stop()
        client = nil
        readyFired = false
    }

    func handleLocalPacket(packet: Data) {
        client?.sendLocalSRT(packet)
    }

    func connectionStatistics() -> [BondingConnection] {
        guard let client else { return [] }
        return links.indices.compactMap { i -> BondingConnection? in
            let s = client.linkStats(i)
            guard s.registered else { return nil }
            return BondingConnection(
                name: links[i].interfaceType.map(Self.name(for:)) ?? "link\(i)",
                usage: 0, // per-link byte deltas: future (needs FFI counters)
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
