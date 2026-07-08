import Foundation
import Network
import os

/// The IO shell around the sans-IO `IrltpSender`: it owns one UDP
/// `NWConnection` per bonded link (optionally pinned to a specific interface),
/// a monotonic clock, and a ~10 ms tick, and translates the session's
/// `[IrltpAction]` into real socket work.
///
/// Feed it the local SRT stream via ``sendLocalSRT(_:)``; replies from the
/// receiver come back through ``onForwardToLocalSrt``. All access to the
/// (single, mutable) session is serialized on one queue.
public final class IRLTPBondingClient {
    /// One bonded path: where to reach the receiver, and which interface to pin.
    public struct Link {
        public let interface: NWInterface?
        public let interfaceType: NWInterface.InterfaceType?
        public init(interface: NWInterface? = nil, interfaceType: NWInterface.InterfaceType? = nil) {
            self.interface = interface
            self.interfaceType = interfaceType
        }
    }

    /// Per-link snapshot for stats/UI.
    public struct LinkSnapshot {
        public let interfaceType: NWInterface.InterfaceType?
        public let registered: Bool
        public let rttMs: UInt32?
        public let txBytes: UInt64
        public let rxBytes: UInt64
    }

    /// Replies from the receiver (SRT ACK/NAK, and any downlink SRT) to hand
    /// back to the local SRT endpoint.
    public var onForwardToLocalSrt: ((Data) -> Void)?
    /// Fires once, when the first link registers and the bond is usable.
    public var onSessionEstablished: (() -> Void)?

    private let sender: IrltpSender
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let links: [Link]
    private let queue = DispatchQueue(label: "irltp.bonding")
    private var connections: [NWConnection?]
    private var ticker: DispatchSourceTimer?
    private var started = false
    private let epoch = DispatchTime.now().uptimeNanoseconds
    private let log = Logger(subsystem: "com.uxirl.irltp", category: "bonding")
    private var txBytes: [UInt64]
    private var rxBytes: [UInt64]
    private var tickCount = 0
    private var establishedLogged = false

    public init(receiverHost: String, receiverPort: UInt16, links: [Link]) {
        precondition(!links.isEmpty, "need at least one link")
        self.sender = IrltpSender(linkCount: UInt32(links.count))
        self.host = NWEndpoint.Host(receiverHost)
        self.port = NWEndpoint.Port(rawValue: receiverPort)!
        self.links = links
        self.connections = Array(repeating: nil, count: links.count)
        self.txBytes = Array(repeating: 0, count: links.count)
        self.rxBytes = Array(repeating: 0, count: links.count)
    }

    /// Monotonic milliseconds since construction, for the session's timers.
    private func nowMs() -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds - epoch) / 1_000_000
    }

    private func ifaceName(_ i: Int) -> String {
        switch links[i].interfaceType {
        case .cellular: return "cell"
        case .wifi: return "wifi"
        case .wiredEthernet: return "eth"
        default: return "link\(i)"
        }
    }

    public func start() {
        queue.async {
            guard !self.started else { return }
            self.started = true
            self.log.notice("start -> \(self.host.debugDescription, privacy: .public):\(self.port.rawValue) links=\(self.links.count)")
            for i in self.links.indices { self.openConnection(i) }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                self.execute(self.sender.tick(nowMs: self.nowMs()))
                self.tickCount += 1
                if self.tickCount % 100 == 0 { self.logStats() } // ~1s
            }
            t.resume()
            self.ticker = t
        }
    }

    public func stop() {
        queue.async {
            self.log.notice("stop")
            self.ticker?.cancel()
            self.ticker = nil
            for c in self.connections {
                c?.stateUpdateHandler = nil // intentional teardown: no callbacks
                c?.cancel()
            }
            self.connections = Array(repeating: nil, count: self.links.count)
            self.started = false
        }
    }

    /// Feed one datagram from the local SRT endpoint into the bond.
    public func sendLocalSRT(_ data: Data) {
        queue.async {
            self.execute(self.sender.feedLocalSrt(data: data, nowMs: self.nowMs()))
        }
    }

    /// Snapshot of a link's telemetry (thread-safe).
    public func linkStats(_ link: Int) -> IrltpLinkStats {
        sender.linkStats(link: UInt32(link))
    }

    /// Per-link snapshot (registration, rtt, bytes) for the UI.
    public func snapshot() -> [LinkSnapshot] {
        queue.sync {
            links.indices.map { i in
                let s = sender.linkStats(link: UInt32(i))
                return LinkSnapshot(
                    interfaceType: links[i].interfaceType,
                    registered: s.registered,
                    rttMs: s.rttMs,
                    txBytes: txBytes[i],
                    rxBytes: rxBytes[i]
                )
            }
        }
    }

    // MARK: - transport (all on `queue`)

    private func logStats() {
        for i in links.indices {
            let s = sender.linkStats(link: UInt32(i))
            let rtt = s.rttMs.map { "\($0)ms" } ?? "-"
            log.notice("\(self.ifaceName(i), privacy: .public) reg=\(s.registered) win=\(s.window) rtt=\(rtt, privacy: .public) tx=\(self.txBytes[i]) rx=\(self.rxBytes[i]) inflight=\(s.inFlight)")
        }
    }

    private func openConnection(_ i: Int) {
        let params = NWParameters.udp
        params.prohibitExpensivePaths = false
        if let iface = links[i].interface {
            params.requiredInterface = iface
        } else if let type = links[i].interfaceType {
            params.requiredInterfaceType = type
        }
        let conn = NWConnection(host: host, port: port, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.notice("\(self.ifaceName(i), privacy: .public) ready")
                self.execute(self.sender.linkReady(link: UInt32(i), nowMs: self.nowMs()))
            case let .waiting(err):
                // e.g. cellular path unsatisfied while wifi is primary — this is
                // why a link may never register.
                self.log.notice("\(self.ifaceName(i), privacy: .public) waiting: \(String(describing: err), privacy: .public)")
            case let .failed(err):
                self.log.error("\(self.ifaceName(i), privacy: .public) failed: \(String(describing: err), privacy: .public)")
                self.execute(self.sender.linkFailed(link: UInt32(i), nowMs: self.nowMs()))
            // .cancelled is intentional teardown (reconnect/stop) and MUST NOT
            // re-trigger linkFailed — that caused an infinite reconnect churn.
            default:
                break
            }
        }
        connections[i] = conn
        receiveLoop(conn, link: i)
        conn.start(queue: queue)
    }

    private func receiveLoop(_ conn: NWConnection, link: Int) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.rxBytes[link] += UInt64(data.count)
                self.execute(self.sender.feedLink(link: UInt32(link), data: data, nowMs: self.nowMs()))
            }
            if error == nil, self.connections[link] === conn {
                self.receiveLoop(conn, link: link)
            }
        }
    }

    private func execute(_ actions: [IrltpAction]) {
        for action in actions {
            switch action {
            case let .send(link, data):
                let i = Int(link)
                txBytes[i] += UInt64(data.count)
                connections[i]?.send(content: data, completion: .contentProcessed { _ in })
            case let .forwardToLocalSrt(data):
                onForwardToLocalSrt?(data)
            case let .reconnect(link):
                let i = Int(link)
                log.notice("\(self.ifaceName(i), privacy: .public) reconnect")
                connections[i]?.stateUpdateHandler = nil // no .cancelled callback
                connections[i]?.cancel()
                connections[i] = nil
                openConnection(i)
            case .sessionEstablished:
                if !establishedLogged { establishedLogged = true; log.notice("session established") }
                onSessionEstablished?()
            }
        }
    }
}
