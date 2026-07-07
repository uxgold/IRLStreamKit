import Foundation
import Network

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

    public init(receiverHost: String, receiverPort: UInt16, links: [Link]) {
        precondition(!links.isEmpty, "need at least one link")
        self.sender = IrltpSender(linkCount: UInt32(links.count))
        self.host = NWEndpoint.Host(receiverHost)
        self.port = NWEndpoint.Port(rawValue: receiverPort)!
        self.links = links
        self.connections = Array(repeating: nil, count: links.count)
    }

    /// Monotonic milliseconds since construction, for the session's timers.
    private func nowMs() -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds - epoch) / 1_000_000
    }

    public func start() {
        queue.async {
            guard !self.started else { return }
            self.started = true
            for i in self.links.indices { self.openConnection(i) }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                self.execute(self.sender.tick(nowMs: self.nowMs()))
            }
            t.resume()
            self.ticker = t
        }
    }

    public func stop() {
        queue.async {
            self.ticker?.cancel()
            self.ticker = nil
            for c in self.connections { c?.cancel() }
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

    /// Snapshot of a link's telemetry (thread-safe; the session locks).
    public func linkStats(_ link: Int) -> IrltpLinkStats {
        sender.linkStats(link: UInt32(link))
    }

    // MARK: - transport (all on `queue`)

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
                self.execute(self.sender.linkReady(link: UInt32(i), nowMs: self.nowMs()))
            case .failed, .cancelled:
                self.execute(self.sender.linkFailed(link: UInt32(i), nowMs: self.nowMs()))
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
                connections[Int(link)]?.send(content: data, completion: .contentProcessed { _ in })
            case let .forwardToLocalSrt(data):
                onForwardToLocalSrt?(data)
            case let .reconnect(link):
                let i = Int(link)
                connections[i]?.cancel()
                connections[i] = nil
                openConnection(i)
            case .sessionEstablished:
                onSessionEstablished?()
            }
        }
    }
}
