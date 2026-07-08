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
final class IRLTPBondingAdapter: LocalSrtBonding, LocalSrtPortReceiving {
    private weak var delegate: (any SrtlaDelegate)?
    private let links: [IRLTPBondingClient.Link]
    private var client: IRLTPBondingClient?
    private var readyFired = false

    // Official libsrt mode: the SRT engine is libsrt (SrtStreamOfficial), which
    // sends via a callback -> handleLocalPacket -> bond. For inbound we DON'T use
    // a loopback listener libsrt connects to: with the send-callback set, libsrt
    // never transmits on its socket, so such a listener never learns the address
    // to reply to (the observed dead-inbound bug). Instead we own a UDP socket
    // bound to `injector.localPort`, tell libsrt to connect there (srtlaReady),
    // then -- once Media hands us libsrt's own bound port via setLocalSrtPort --
    // inject bond-inbound straight to it from our socket (the peer libsrt
    // expects). srtlaReady fires once BOTH the bond has registered and our socket
    // is up. (Accessed on srtlaClientQueue.)
    private var injector: LoopbackInjector?
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
            // Official mode: inject inbound SRT straight into libsrt's socket.
            self.injector?.send(data)
        }

        let injector = LoopbackInjector()
        injector.onError = { [weak self] message in
            self?.delegate?.srtlaError(message: "IRLTP inject socket: \(message)")
        }
        guard injector.start() else {
            delegate?.srtlaError(message: "IRLTP: could not open local inject socket")
            return
        }

        self.client = client
        self.injector = injector
        srtlaClientQueue.async { [weak self] in
            self?.listenerPort = injector.localPort
            self?.maybeFireReady()
        }
        client.start()
        startDiag()
    }

    /// Media hands over libsrt's bound local UDP port once the official engine
    /// opens; from here inbound SRT can be injected straight to it.
    func setLocalSrtPort(_ port: UInt16) {
        injector?.setTarget(port: port)
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
        injector?.stop()
        injector = nil
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

/// A loopback UDP socket the official SRT engine connects to. libsrt sends its
/// output via the send-callback (to the bond), not on this socket, so we never
/// see a "connection" form -- which is exactly why we don't use `NWListener`.
/// Instead we bind a plain UDP socket, publish its `localPort` for libsrt to
/// connect to, and once `setTarget(port:)` gives us libsrt's own bound port we
/// inject bond-inbound straight to `127.0.0.1:<target>` from this socket -- the
/// peer address libsrt's connected socket accepts. Inbound that arrives before
/// the target is known is briefly buffered.
private final class LoopbackInjector {
    private(set) var localPort: UInt16 = 0
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "irltp.inject")
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var target: UInt16?
    private var pending: [Data] = []
    private static let maxPending = 256

    /// Bind to 127.0.0.1:0 and record the OS-chosen port. Synchronous; returns
    /// false if the socket could not be created/bound.
    func start() -> Bool {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return false }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(sock, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(sock); return false }
        var named = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let gotName = withUnsafeMutablePointer(to: &named) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(sock, sockaddrPointer, &length)
            }
        }
        guard gotName == 0 else { close(sock); return false }
        fd = sock
        localPort = UInt16(bigEndian: named.sin_port)
        // Drain whatever libsrt sends here (tap case) so the recv buffer never
        // stalls; we forward nothing -- its real output already reached the bond.
        let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 2048)
            _ = recv(self.fd, &buffer, buffer.count, 0)
        }
        source.setCancelHandler { close(sock) }
        source.resume()
        readSource = source
        return true
    }

    /// Learn libsrt's bound local port and flush anything buffered so far.
    func setTarget(port: UInt16) {
        queue.async {
            self.target = port
            let flush = self.pending
            self.pending.removeAll()
            for data in flush { self.sendLocked(data) }
        }
    }

    /// Inject one inbound SRT datagram toward libsrt.
    func send(_ data: Data) {
        queue.async {
            guard self.target != nil else {
                if self.pending.count < Self.maxPending { self.pending.append(data) }
                return
            }
            self.sendLocked(data)
        }
    }

    func stop() {
        queue.sync {
            readSource?.cancel() // cancel handler closes fd
            readSource = nil
            fd = -1
            target = nil
            pending.removeAll()
        }
    }

    private func sendLocked(_ data: Data) {
        guard fd >= 0, let target else { return }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = in_port_t(bigEndian: target)
        let sent = data.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(fd, raw.baseAddress, raw.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 { onError?("sendto failed (errno \(errno))") }
    }
}
