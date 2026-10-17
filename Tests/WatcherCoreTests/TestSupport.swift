import AsyncHTTPClient
import CryptoKit
import Foundation
import NIO
import NIOHTTP1
@testable import WatcherCore
import XCTest

/// Tiny HTTP origin that echoes what it received.
final class TestUpstream {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private(set) var port = 0
    private var channel: Channel?

    func start() async throws {
        channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap { channel.pipeline.addHandler(EchoHandler()) }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        port = channel!.localAddress!.port!
    }

    func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}

private final class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private var head: HTTPRequestHead?
    private var receivedBytes = 0

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head): self.head = head; receivedBytes = 0
        case let .body(buffer): receivedBytes += buffer.readableBytes
        case .end:
            guard let head else { return }
            if head.uri == "/redirect" {
                context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .found, headers: ["Location": "/final", "Content-Length": "0"]))), promise: nil)
                return context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }
            // No body although a length is announced: HEAD and 304 describe a body they do not send.
            if head.method == .HEAD || head.uri == "/notmodified" {
                let status: HTTPResponseStatus = head.method == .HEAD ? .ok : .notModified
                context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: ["Content-Length": "42", "ETag": "\"v1\""]))), promise: nil)
                return context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }
            // Bodiless answers: a declared zero length, a 204, and an empty body ended by closing the connection.
            if head.uri == "/empty" || head.uri == "/nocontent" || head.uri == "/close" {
                let status: HTTPResponseStatus = head.uri == "/nocontent" ? .noContent : .ok
                let headers: HTTPHeaders = head.uri == "/empty" ? ["Content-Length": "0"] : head.uri == "/close" ? ["Connection": "close"] : [:]
                context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))), promise: nil)
                let done = context.writeAndFlush(wrapOutboundOut(.end(nil)))
                if head.uri == "/close" {
                    done.whenComplete { _ in context.close(promise: nil) }
                }
                return
            }
            let text = "\(head.method.rawValue) \(head.uri) host=\(head.headers.first(name: "Host") ?? "-") script=\(head.headers.first(name: "X-Script") ?? "-") bytes=\(receivedBytes)"
            var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            let headers: HTTPHeaders = ["Content-Length": "\(buffer.readableBytes)", "Content-Type": "text/plain"]
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers))), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

/// Engine + echo origin + a client that talks through the proxy. `upstream.test` resolves to the echo origin.
final class Harness {
    let upstream = TestUpstream()
    let engine: WatcherEngine
    let client: HTTPClient
    var proxyPort = 0
    var originURL: String {
        "http://upstream.test:\(upstream.port)"
    }

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)")
        engine = try WatcherEngine(directory: directory)
        client = HTTPClient(eventLoopGroupProvider: .singleton)
    }

    func start(configure: (inout WatcherSettings) -> Void = { _ in }) async throws {
        try await upstream.start()
        try engine.settings.update {
            $0.dnsSpoofing = RuleSet(isEnabled: true, rules: [DNSSpoofRule(host: "upstream.test", address: "127.0.0.1")])
            configure(&$0)
        }
        proxyPort = try await engine.start(port: 0)
    }

    func reconfigure(_ change: (inout WatcherSettings) -> Void) async throws {
        try engine.settings.update(change)
        await engine.apply(engine.settings.value)
    }

    /// Plain-HTTP request through the proxy (absolute-form URI, like a browser would send).
    func get(_ path: String, method: String = "GET", headers: [(String, String)] = []) async throws -> (status: Int, body: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": proxyPort]
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: URL(string: originURL + path)!)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }

    func post(_ path: String, body: Data) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": proxyPort]
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: originURL + path)!)
        request.httpMethod = "POST"
        let (data, _) = try await session.upload(for: request, from: body)
        return String(decoding: data, as: UTF8.self)
    }

    func stop() async {
        try? await engine.stop(); await upstream.stop(); try? await client.shutdown()
    }
}

/// Direct (non-proxied) fetch used where the test talks to a listener itself.
enum HTTPClientRequestHelper {
    static func url(_ string: String) -> URL {
        URL(string: string)!
    }

    static func fetch(_ url: URL) async throws -> String {
        let (data, _) = try await URLSession(configuration: .ephemeral).data(from: url)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Raw TCP origin that answers an upgrade request with 101 and then echoes every byte.
final class UpgradeOrigin {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private(set) var port = 0
    private var channel: Channel?

    func start() async throws {
        channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(UpgradeEcho()) }
            .bind(host: "127.0.0.1", port: 0).get()
        port = channel!.localAddress!.port!
    }

    func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}

private final class UpgradeEcho: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private var upgraded = false
    private var pending = Data()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if upgraded {
            return write(context, buffer)
        }
        pending.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
        guard pending.range(of: Data("\r\n\r\n".utf8)) != nil else { return }
        upgraded = true
        write(context, context.channel.allocator.buffer(string: "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"))
    }

    private func write(_ context: ChannelHandlerContext, _ buffer: ByteBuffer) {
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }
}

/// Raw TCP client that accumulates whatever it receives.
final class RawClient {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let sink = Sink()
    private var channel: Channel!

    func connect(port: Int) async throws {
        channel = try await ClientBootstrap(group: group)
            .channelInitializer { [sink] in $0.pipeline.addHandler(sink) }
            .connect(host: "127.0.0.1", port: port).get()
    }

    func send(_ text: String) async throws {
        try await channel.writeAndFlush(channel.allocator.buffer(string: text))
    }

    func send(bytes: [UInt8]) async throws {
        try await channel.writeAndFlush(channel.allocator.buffer(bytes: bytes))
    }

    func receivedBytes(atLeast count: Int, timeout: TimeInterval = 5) async -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, sink.raw.count < count {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return sink.raw
    }

    func received(containing needle: String, timeout: TimeInterval = 5) async -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = sink.text
            if text.contains(needle) {
                return text
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return sink.text
    }

    func close() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }

    private final class Sink: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer
        private let lock = NSLock()
        private var data = Data()
        var text: String {
            lock.withLock { String(decoding: data, as: UTF8.self) }
        }

        var raw: [UInt8] {
            lock.withLock { Array(data) }
        }

        func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
            var buffer = unwrapInboundIn(data)
            lock.withLock { self.data.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? []) }
        }
    }
}

/// Raw TCP origin streaming a chunked event-stream: one event immediately, the next after `delay`.
final class StreamOrigin {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let delay: TimeAmount
    private(set) var port = 0
    private var channel: Channel?

    init(delay: TimeAmount = .milliseconds(1200)) {
        self.delay = delay
    }

    func start() async throws {
        let delay = delay
        channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(StreamHandler(delay: delay)) }
            .bind(host: "127.0.0.1", port: 0).get()
        port = channel!.localAddress!.port!
    }

    func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}

private final class StreamHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private let delay: TimeAmount
    private var pending = Data()
    private var started = false

    init(delay: TimeAmount) {
        self.delay = delay
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        pending.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
        guard !started, pending.range(of: Data("\r\n\r\n".utf8)) != nil else { return }
        started = true
        send(context, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\nb\r\ndata: one\n\n\r\n")
        let loop = context.eventLoop
        let channel = context.channel
        loop.scheduleTask(in: delay) {
            channel.writeAndFlush(channel.allocator.buffer(string: "b\r\ndata: two\n\n\r\n0\r\n\r\n"), promise: nil)
        }
    }

    private func send(_ context: ChannelHandlerContext, _ text: String) {
        context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(string: text)), promise: nil)
    }
}

/// A real RFC 6455 echo server: completes the handshake (Sec-WebSocket-Accept) and answers each text frame with the same text.
final class WebSocketEchoOrigin {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private(set) var port = 0
    private var channel: Channel?

    func start() async throws {
        channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(WebSocketEcho()) }
            .bind(host: "127.0.0.1", port: 0).get()
        port = channel!.localAddress!.port!
    }

    func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}

private final class WebSocketEcho: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private var parser = WebSocketFrameParser()
    private var pending = Data()
    private var upgraded = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        guard upgraded else {
            pending.append(contentsOf: bytes)
            guard let end = pending.range(of: Data("\r\n\r\n".utf8)) else { return }
            let head = String(decoding: pending[..<end.lowerBound], as: UTF8.self)
            let key = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("sec-websocket-key:") }?
                .dropFirst("sec-websocket-key:".count).trimmingCharacters(in: .whitespaces) ?? ""
            let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
            upgraded = true
            send(context, Array("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8))
            echo(context, Array(pending[end.upperBound...]))
            return
        }
        echo(context, bytes)
    }

    private func echo(_ context: ChannelHandlerContext, _ bytes: [UInt8]) {
        for message in parser.feed(bytes) where message.kind == .text && message.payload.count < 126 {
            send(context, [0x81, UInt8(message.payload.count)] + Array(message.payload))
        }
    }

    private func send(_ context: ChannelHandlerContext, _ bytes: [UInt8]) {
        context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(bytes: bytes)), promise: nil)
    }
}

/// Runs a short Python script (the system `python3` has `ssl`) and returns what it printed; skips the test if python3 is missing.
func runPython(_ script: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-c", script]
    let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { throw XCTSkip("python3 unavailable") }
    process.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

/// Python source for "CONNECT host:443 through the proxy, then a TLS handshake"; the caller appends statements that use `t` or `err`.
func pythonTLSViaProxy(port: Int, host: String, verify: Bool, alpn: [String] = []) -> String {
    """
    import socket, ssl
    s = socket.create_connection(("127.0.0.1", \(port)), timeout=10)
    s.sendall(b"CONNECT \(host):443 HTTP/1.1\\r\\nHost: \(host):443\\r\\n\\r\\n"); s.recv(4096)
    ctx = ssl.create_default_context()
    \(verify ? "" : "ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE")
    \(alpn.isEmpty ? "" : "ctx.set_alpn_protocols([\(alpn.map { "\"\($0)\"" }.joined(separator: ", "))])")
    t = None; err = None
    try: t = ctx.wrap_socket(s, server_hostname="\(host)")
    except Exception as e: err = e
    """
}

extension Harness {
    /// GET through the proxy that also returns the response headers.
    func getWithHeaders(_ path: String) async throws -> (status: Int, headers: [String: String]) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": proxyPort]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(from: URL(string: originURL + path)!)
        let http = response as! HTTPURLResponse
        return (http.statusCode, Dictionary(uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value in (key as? String).map { ($0.lowercased(), "\(value)") } }))
    }
}

/// Accepts connections and never answers: for timeout tests.
final class SilentOrigin {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private(set) var port = 0
    private var channel: Channel?

    func start() async throws {
        channel = try await ServerBootstrap(group: group).childChannelInitializer { $0.pipeline.addHandler(SilentSink()) }.bind(host: "127.0.0.1", port: 0).get()
        port = channel!.localAddress!.port!
    }

    func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}

private final class SilentSink: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    func channelRead(context _: ChannelHandlerContext, data _: NIOAny) {}
}
