import AVFoundation
import Foundation
import libsrt
import os

// IRLTP integration (Shim): diagnostic logger that reaches the device syslog
// (the vendored `logger` uses a custom sink that idevicesyslog can't see).
private let srtDiag = Logger(subsystem: "com.uxirl.irltp", category: "srt")

protocol SrtStreamOfficialDelegate: AnyObject {
    func srtStreamOfficialError()
}

private enum ReadyState: UInt8 {
    case initialized
    case publishing
}

private class SendHook {
    var closure: ((Data) -> Bool)?

    init(closure: ((Data) -> Bool)?) {
        self.closure = closure
    }
}

class SrtStreamOfficial: @unchecked Sendable {
    private let writer: MpegTsWriter
    private var sendHook = SendHook(closure: nil)
    // IRLTP integration (Shim): when set, connect() binds the socket to a known
    // local port and reports it here BEFORE the blocking srt_connect, so the
    // bonding transport can aim its inbound injector at libsrt before the SRT
    // handshake starts. nil on the default path (Moblin SRTLA / plain SRT).
    private var onLocalPort: ((UInt16) -> Void)?
    private var writerOutputCount = 0
    private var options: [SrtSocketOption: String] = [:]
    private var perf = CBytePerfMon()
    private var socket: SRTSOCKET = SRT_INVALID_SOCK
    weak var srtStreamDelegate: (any SrtStreamOfficialDelegate)?
    private let processor: Processor

    private var readyState: ReadyState = .initialized {
        didSet {
            guard oldValue != readyState else {
                return
            }
            logger.info("srt: State change \(oldValue) -> \(readyState)")
            switch oldValue {
            case .publishing:
                logger.info("srt: Stop publishing")
                writer.stopRunning()
                processor.stopEncoding(writer)
            default:
                break
            }
            switch readyState {
            case .publishing:
                logger.info("srt: Start publishing")
                processor.startEncoding(writer)
                writer.startRunning()
            default:
                break
            }
        }
    }

    init(processor: Processor, timecodesEnabled: Bool, delegate: any SrtStreamOfficialDelegate) {
        self.processor = processor
        writer = MpegTsWriter(timecodesEnabled: timecodesEnabled, newSrt: false)
        srtStreamDelegate = delegate
        writer.delegate = self
        srt_startup()
    }

    deinit {
        srt_cleanup()
    }

    func open(_ uri: URL?, onLocalPort: ((UInt16) -> Void)? = nil, sendHook: @escaping (Data) -> Bool) throws {
        guard let uri, uri.scheme == "srt", let host = uri.host, let port = uri.port else {
            return
        }
        self.sendHook = SendHook(closure: sendHook)
        self.onLocalPort = onLocalPort
        socket = SRT_INVALID_SOCK
        var options = SrtSocketOption.from(uri: uri)
        options[.sndsyn] = "0"
        try connect(sockaddrIn(host, port: UInt16(clamping: port)), options)
    }

    func close() {
        processorControlQueue.async {
            self.readyState = .initialized
            guard self.socket != SRT_INVALID_SOCK else {
                return
            }
            srt_close(self.socket)
            self.socket = SRT_INVALID_SOCK
        }
    }

    func getPerformanceData() -> SrtPerformanceData {
        guard socket != SRT_INVALID_SOCK else {
            return .zero
        }
        _ = srt_bstats(socket, &perf, 1)
        return SrtPerformanceData(mon: perf)
    }

    // IRLTP integration (Shim): the local UDP port libsrt bound after connect.
    // The IRLTP bond needs this to inject inbound SRT straight into libsrt's
    // socket, because with the send-callback set libsrt never transmits on that
    // socket — so a loopback listener would never learn the address to reply to.
    // Additive, off the default path (only read when the IRLTP adapter is the
    // bonding transport). Callers must read it on processorControlQueue.
    func localUdpPort() -> UInt16? {
        guard socket != SRT_INVALID_SOCK else {
            return nil
        }
        var addr = sockaddr_in()
        var len = Int32(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &addr) { addrPointer -> Int32 in
            addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                srt_getsockname(socket, sockaddrPointer, &len)
            }
        }
        guard result != SRT_ERROR else {
            return nil
        }
        let port = UInt16(bigEndian: addr.sin_port)
        return port != 0 ? port : nil
    }

    func getSndData() -> Int32 {
        guard socket != SRT_INVALID_SOCK else {
            return SRT_ERROR
        }
        var sndData: Int32 = 0
        var size = Int32(MemoryLayout<Int32>.size)
        let result = withUnsafeMutablePointer(to: &sndData) { sndDataPointer -> Int32 in
            srt_getsockflag(
                socket,
                SRTO_SNDDATA,
                sndDataPointer,
                &size
            )
        }
        if result == SRT_ERROR {
            // To do: check result
        }
        return sndData
    }

    private func sockaddrIn(_ host: String, port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(bigEndian: port)
        guard let hostent = gethostbyname(host), hostent.pointee.h_addrtype == AF_INET else {
            return addr
        }
        addr.sin_addr = UnsafeRawPointer(hostent.pointee.h_addr_list[0]!)
            .assumingMemoryBound(to: in_addr.self).pointee
        return addr
    }

    private func connect(_ addr: sockaddr_in, _ options: [SrtSocketOption: String]) throws {
        guard socket == SRT_INVALID_SOCK else {
            return
        }
        socket = srt_create_socket()
        if socket == SRT_INVALID_SOCK {
            throw makeSocketError()
        }
        let context = Unmanaged.passRetained(sendHook).toOpaque()
        srt_send_callback(socket,
                          { context, _, buf1, size1, buf2, size2 in
                              guard let context, let buf1, let buf2 else {
                                  return -1
                              }
                              let sendHook: SendHook = Unmanaged.fromOpaque(context).takeUnretainedValue()
                              var data = Data(capacity: Int(size1 + size2))
                              buf1.withMemoryRebound(to: UInt8.self, capacity: Int(size1)) { buf in
                                  data.append(buf, count: Int(size1))
                              }
                              buf2.withMemoryRebound(to: UInt8.self, capacity: Int(size2)) { buf in
                                  data.append(buf, count: Int(size2))
                              }
                              if sendHook.closure?(data) ?? false {
                                  return size1 + size2
                              } else {
                                  return -1
                              }
                          },
                          context)
        self.options = options
        guard configure(.pre) else {
            throw makeSocketError()
        }
        // IRLTP integration (Shim): bind to a known local UDP port and hand it to
        // the bonding transport BEFORE srt_connect. srt_connect blocks until the
        // SRT handshake completes, and that handshake's reply arrives via the bond
        // — so the injector must already be pointed at libsrt's socket when the
        // reply lands, otherwise it is buffered forever and the handshake times
        // out (the on-device out[data]=0 / "connection timed out" deadlock).
        srtDiag.notice("connect: pre-configured, onLocalPort=\(self.onLocalPort != nil, privacy: .public)")
        if let onLocalPort {
            var local = sockaddr_in()
            local.sin_family = sa_family_t(AF_INET)
            local.sin_addr.s_addr = inet_addr("127.0.0.1")
            local.sin_port = 0
            let bound = withUnsafePointer(to: &local) { localPointer -> Int32 in
                localPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    srt_bind(socket, sockaddrPointer, Int32(MemoryLayout<sockaddr_in>.size))
                }
            }
            let localPort = localUdpPort()
            srtDiag.notice("connect: srt_bind result=\(bound, privacy: .public) L=\(localPort.map { Int($0) } ?? -1, privacy: .public)")
            if bound != SRT_ERROR, let localPort {
                onLocalPort(localPort)
            } else {
                srtDiag.error("connect: bind-before-connect failed; inbound may stall")
            }
        }
        var addrCopy = addr
        srtDiag.notice("connect: srt_connect start")
        let result = withUnsafePointer(to: &addrCopy) { addrCopyPointer -> Int32 in
            srt_connect(
                socket,
                UnsafeRawPointer(addrCopyPointer).assumingMemoryBound(to: sockaddr.self),
                Int32(MemoryLayout.size(ofValue: addr))
            )
        }
        srtDiag.notice("connect: srt_connect result=\(result, privacy: .public)")
        if result == SRT_ERROR {
            let message = makeSocketError()
            srtDiag.error("connect: srt_connect failed: \(message, privacy: .public)")
            throw message
        }
        guard configure(.post) else {
            let message = makeSocketError()
            srtDiag.error("connect: configure(.post) failed: \(message, privacy: .public)")
            throw message
        }
        srtDiag.notice("connect: publishing (handshake accepted, encoder starting)")
        readyState = .publishing
    }

    private func configure(_ binding: SrtSocketOption.Binding) -> Bool {
        let failures = SrtSocketOption.configure(socket, binding: binding, options: options)
        guard failures.isEmpty else {
            logger.info("srt: configure failures: \(failures)")
            return false
        }
        return true
    }

    private func makeSocketError() -> String {
        guard let lastError = srt_getlasterror_str() else {
            return "Last error not set"
        }
        var message = String(cString: lastError)
        switch srt_getlasterror(nil) {
        case SRT_ECONNREJ.rawValue:
            if let rejectReason = srt_rejectreason_str(srt_getrejectreason(socket)) {
                message += ": " + String(cString: rejectReason)
            }
        default:
            break
        }
        return message
    }
}

extension SrtStreamOfficial: MpegTsWriterDelegate {
    func writer(_: MpegTsWriter, doOutput data: Data, containsAudio _: Bool) {
        let sent = data.withUnsafeBytes { pointer -> Int32 in
            guard let buffer = pointer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                logger.info("srt: error buffer size \(data.count)")
                return SRT_ERROR
            }
            return srt_sendmsg2(socket, buffer, Int32(data.count), nil)
        }
        diagWriterOutput(bytes: data.count, sent: sent)
        if Int(sent) != data.count {
            processorControlQueue.async {
                self.readyState = .initialized
                self.srtStreamDelegate?.srtStreamOfficialError()
            }
        }
    }

    func writer(_: MpegTsWriter, doOutputPointer pointer: UnsafeRawBufferPointer, count: Int) {
        guard let buffer = pointer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
            return
        }
        let sent = srt_sendmsg2(socket, buffer, Int32(count), nil)
        diagWriterOutput(bytes: count, sent: sent)
        if Int(sent) != count {
            processorControlQueue.async {
                self.readyState = .initialized
                self.srtStreamDelegate?.srtStreamOfficialError()
            }
        }
    }

    // IRLTP integration (Shim): localise "connected but no data" — is the encoder
    // even handing MPEG-TS to the SRT socket, and is srt_sendmsg2 accepting it?
    private func diagWriterOutput(bytes: Int, sent: Int32) {
        writerOutputCount += 1
        if writerOutputCount == 1 {
            srtDiag.notice("writer.doOutput first output bytes=\(bytes, privacy: .public) sent=\(sent, privacy: .public) — media is flowing")
        }
        if Int(sent) != bytes {
            srtDiag.error("writer.doOutput srt_sendmsg2 failed sent=\(sent, privacy: .public) want=\(bytes, privacy: .public)")
        }
    }
}
