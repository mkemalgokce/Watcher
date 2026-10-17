import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1
import NIOSSL

/// Handles one client connection: plain proxy requests, CONNECT tunnels (decrypted or blind) and requests inside a decrypted tunnel.
final class ProxyConnectionHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: ProxyServer
    private let codecs: [RemovableChannelHandler]
    private let origin: ReverseOrigin?
    /// True for a handler serving one HTTP/2 stream: no CONNECT, no upgrades, no connection-level headers.
    private let isHTTP2: Bool
    /// The request decoder currently in the pipeline (replaced after a decrypted CONNECT); nil on HTTP/2 streams.
    private var decoder: RemovableChannelHandler?
    private var head: HTTPRequestHead?
    private var body = Data()
    private var tooLarge = false
    /// Set after a CONNECT (or SOCKS) we handle ourselves: every request now belongs to this origin.
    private var tunnel: (scheme: String, host: String, port: Int)?
    /// Feeds a large upload to the upstream while it is still arriving.
    private var upload: AsyncStream<ByteBuffer>.Continuation?
    private let clientApp = ClientAppResolver()
    private let details: ConnectionDetails

    init(
        server: ProxyServer,
        codecs: [RemovableChannelHandler],
        origin: ReverseOrigin?,
        tunnel: (scheme: String, host: String, port: Int)? = nil,
        isHTTP2: Bool = false,
        details: ConnectionDetails = ConnectionDetails()
    ) {
        self.details = details
        self.server = server; self.codecs = codecs; self.origin = origin; self.tunnel = tunnel; self.isHTTP2 = isHTTP2
        decoder = codecs.count > 1 ? codecs[1] : nil
    }

    private func keepAlive(_ head: HTTPRequestHead) -> Bool {
        isHTTP2 || head.isKeepAlive
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            self.head = head; body = Data(); tooLarge = false
            startUploadIfLarge(context.channel, head)
        case var .body(buffer):
            if let upload {
                upload.yield(buffer); return
            }
            guard body.count + buffer.readableBytes <= ProxyServer.maxBodyBytes else { tooLarge = true; return }
            body.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
        case .end:
            guard let head else { return }
            self.head = nil
            if let upload {
                upload.finish(); self.upload = nil; return
            }
            if tooLarge {
                return respond(ProxyServer.message(413, "Body too large for Watcher"), to: context.channel, head: head)
            }
            if head.method == .CONNECT {
                if isHTTP2 {
                    respond(ProxyServer.message(501, "CONNECT is not supported over HTTP/2"), to: context.channel, head: head)
                } else {
                    connect(context, head)
                }
            } else {
                forward(context, head)
            }
        }
    }

    // MARK: CONNECT

    private func connect(_ context: ChannelHandlerContext, _ head: HTTPRequestHead) {
        let parts = head.uri.split(separator: ":", maxSplits: 1)
        guard let host = parts.first.map(String.init), !host.isEmpty else {
            return respond(ProxyServer.message(400, "Bad CONNECT target"), to: context.channel, head: head)
        }
        let port = parts.count > 1 ? Int(parts[1]) ?? 443 : 443

        if server.shouldIntercept(host: host), let authority = server.authority {
            do {
                acknowledgeConnect(context).flatMap { [self] in
                    // After CONNECT the decoder switches to raw pass-through; swap in a fresh one for the decrypted stream.
                    guard let decoder else { return context.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel) }
                    return context.pipeline.removeHandler(decoder)
                }.flatMap { [self] in
                    let fresh = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                    decoder = fresh
                    return context.pipeline.addHandler(fresh, position: .before(self))
                }.flatMap { [self] in
                    do {
                        let handlers = try server.tlsHandlers(host: host, http1: [codecs[0], decoder!, self], details: details)
                        return context.pipeline.addHandlers(handlers, position: .first)
                    } catch { return context.eventLoop.makeFailedFuture(error) }
                }.whenComplete { [self] result in
                    switch result {
                    case .success: tunnel = ("https", host, port)
                    case .failure: context.close(promise: nil)
                    }
                }
            } catch {
                respond(ProxyServer.message(502, "TLS setup failed: \(error)"), to: context.channel, head: head)
            }
        } else {
            blindTunnel(context, host: host, port: port, head: head)
        }
    }

    /// Writes the raw `200` straight to the socket; going through the HTTP encoder would append a chunk terminator and corrupt the tunnel.
    private func acknowledgeConnect(_ context: ChannelHandlerContext) -> EventLoopFuture<Void> {
        context.pipeline.context(handler: codecs[0]).flatMap { encoderContext in
            let reply = encoderContext.channel.allocator.buffer(string: "HTTP/1.1 200 Connection Established\r\n\r\n")
            return encoderContext.writeAndFlush(NIOAny(reply))
        }
    }

    private func blindTunnel(_ context: ChannelHandlerContext, host: String, port: Int, head: HTTPRequestHead) {
        let client = context.channel
        ClientBootstrap(group: context.eventLoop).connect(host: server.resolve(host), port: port).whenComplete { [self] result in
            switch result {
            case let .failure(error):
                respond(ProxyServer.message(502, "Tunnel to \(host):\(port) failed: \(error)"), to: client, head: head)
            case let .success(upstream):
                acknowledgeConnect(context).flatMap { [self] in
                    EventLoopFuture.andAllSucceed(codecs.map { context.pipeline.removeHandler($0) }, on: context.eventLoop)
                }.flatMap {
                    context.pipeline.addHandler(RelayHandler(peer: upstream))
                }.flatMap {
                    upstream.pipeline.addHandler(RelayHandler(peer: client))
                }.flatMap {
                    context.pipeline.removeHandler(self)
                }.whenFailure { _ in client.close(promise: nil); upstream.close(promise: nil) }
            }
        }
    }

    // MARK: Requests

    private func forward(_ context: ChannelHandlerContext, _ head: HTTPRequestHead) {
        guard let record = makeRecord(head) else {
            return respond(ProxyServer.message(400, "Cannot determine target host"), to: context.channel, head: head)
        }
        let channel = context.channel
        let server = server
        if origin == nil, tunnel == nil, let page = server.certificatePage,
           CertificatePage.isAddressed(host: record.host, port: record.port, proxyPort: channel.localAddress?.port)
        {
            return respond(page.response(forPath: record.path), to: channel, head: head)
        }
        if !isHTTP2, head.headers.contains(name: "Upgrade") {
            return upgrade(channel, head: head, record: record)
        }
        Task {
            var record = record
            record.clientApp = await self.clientApp.app(for: channel)
            switch await server.serve(record, allowStreaming: true, connection: self.details.summary) {
            case let .buffered(response):
                channel.eventLoop.execute { self.respond(response, to: channel, head: head) }
            case let .streamed(response, body, complete):
                await self.stream(response, body: body, to: channel, head: head, complete: complete)
            }
        }
    }

    /// Bodies above the threshold are streamed upstream as they arrive, unless a tool needs to read the body.
    private func startUploadIfLarge(_ channel: Channel, _ head: HTTPRequestHead) {
        guard head.method != .CONNECT, !head.headers.contains(name: "Upgrade"),
              let length = head.headers.first(name: "Content-Length").flatMap(Int.init), length > ProxyServer.streamingUploadThreshold,
              !server.tools.needsRequestBody, let record = makeRecord(head) else { return }
        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        upload = continuation
        let server = server
        Task {
            var record = record
            record.clientApp = await self.clientApp.app(for: channel)
            switch await server.serve(record, allowStreaming: true, upload: .init(body: stream, length: length), connection: self.details.summary) {
            case let .buffered(response): channel.eventLoop.execute { self.respond(response, to: channel, head: head) }
            case let .streamed(response, body, complete): await self.stream(response, body: body, to: channel, head: head, complete: complete)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        upload?.finish(); upload = nil
        reportAbandonedHandshake()
        context.fireChannelInactive()
    }

    /// A connection we decrypt that ends before the TLS handshake finished: the client did not accept Watcher's certificate.
    private func reportAbandonedHandshake() {
        guard let tunnel, tunnel.scheme == "https", !isHTTP2, !details.isHandshakeDone else { return }
        details.record(tlsVersion: nil, alpn: "abandoned") // report each connection once
        server.handshakeFailed(host: tunnel.host)
    }

    /// WebSocket and other upgrades: swap the HTTP codecs for a raw relay once the upstream is connected.
    private func upgrade(_ client: Channel, head: HTTPRequestHead, record: RequestRecord) {
        let server = server
        Task {
            var record = record
            record.clientApp = await self.clientApp.app(for: client)
            switch await server.prepareUpgrade(record) {
            case let .answer(response):
                client.eventLoop.execute { self.respond(response, to: client, head: head) }
            case let .tunnel(request, flowID):
                do {
                    let recorder = WebSocketRecorder(store: server.store, flowID: flowID)
                    let upstream = try await server.connectUpgrade(request, on: client.eventLoop, client: client, recorder: recorder)
                    try await client.pipeline.removeHandler(codecs[0]).get()
                    if let decoder {
                        try await client.pipeline.removeHandler(decoder).get()
                    }
                    try await client.pipeline.addHandler(RelayHandler(peer: upstream, tap: { recorder.record($0, direction: .clientToServer) })).get()
                    try await client.pipeline.removeHandler(self).get()
                    try await upstream.writeAndFlush(ProxyServer.handshakeBytes(for: request, allocator: upstream.allocator))
                    server.finishUpgrade(flowID, status: 101)
                } catch {
                    let response = server.finishUpgrade(flowID, status: 502, message: "WebSocket tunnel failed: \(error)", state: .failed, error: "\(error)")
                    client.eventLoop.execute { self.respond(response, to: client, head: head) }
                }
            }
        }
    }

    private func makeRecord(_ head: HTTPRequestHead) -> RequestRecord? {
        var headers = head.headers.map { Header($0.name, $0.value) }
        let scheme: String, host: String, port: Int, path: String

        if let origin {
            (scheme, host, port, path) = (origin.scheme, origin.host, origin.port, head.uri)
            if !origin.preserveHost {
                headers.set("Host", host)
            }
        } else if let tunnel {
            (scheme, host, port, path) = (tunnel.scheme, tunnel.host, tunnel.port, head.uri)
        } else if let url = URLComponents(string: head.uri), let urlHost = url.host {
            scheme = url.scheme ?? "http"; host = urlHost
            port = url.port ?? (scheme == "https" ? 443 : 80)
            path = (url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath) + (url.percentEncodedQuery.map { "?\($0)" } ?? "")
        } else if let hostHeader = head.headers.first(name: "Host") {
            let parts = hostHeader.split(separator: ":", maxSplits: 1)
            (scheme, host, port, path) = ("http", String(parts[0]), parts.count > 1 ? Int(parts[1]) ?? 80 : 80, head.uri)
        } else {
            return nil
        }
        return RequestRecord(
            method: head.method.rawValue,
            scheme: scheme,
            host: host,
            port: port,
            path: path,
            headers: headers,
            body: body
        )
    }

    /// Relays the upstream body as it arrives (chunked), keeping a bounded copy for the session list.
    private func stream(
        _ response: ResponseRecord,
        body: HTTPClientResponse.Body,
        to channel: Channel,
        head: HTTPRequestHead,
        complete: @Sendable (Data, Error?) -> Void
    ) async {
        var captured = Data()
        do {
            try await channel.writeAndFlush(HTTPServerResponsePart.head(responseHead(response, bodyLength: nil, keepAlive: keepAlive(head))))
            for try await chunk in body {
                if captured.count < ProxyServer.maxCapturedStreamBytes {
                    captured.append(contentsOf: chunk.readableBytesView)
                }
                if head.method != .HEAD {
                    try await channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(chunk)))
                }
            }
            try await channel.writeAndFlush(HTTPServerResponsePart.end(nil))
            complete(captured, nil)
            if !keepAlive(head) {
                channel.close(promise: nil)
            }
        } catch {
            complete(captured, error)
            channel.close(promise: nil)
        }
    }

    private func responseHead(_ response: ResponseRecord, bodyLength: Int?, keepAlive: Bool) -> HTTPResponseHead {
        var headers = HTTPHeaders()
        for header in response.headers where !ProxyServer.hopByHop.contains(header.name.lowercased()) {
            headers.add(name: header.name, value: header.value)
        }
        if let bodyLength {
            headers.add(name: "Content-Length", value: "\(bodyLength)")
        }
        // Connection-specific headers are forbidden in HTTP/2.
        if !isHTTP2 {
            headers.add(name: "Connection", value: keepAlive ? "keep-alive" : "close")
        }
        return HTTPResponseHead(version: .http1_1, status: .init(statusCode: response.status), headers: headers)
    }

    private func respond(_ response: ResponseRecord, to channel: Channel, head: HTTPRequestHead) {
        let keepAlive = keepAlive(head)
        channel.write(HTTPServerResponsePart.head(responseHead(response, bodyLength: response.body.count, keepAlive: keepAlive)), promise: nil)
        if head.method != .HEAD, !response.body.isEmpty {
            var buffer = channel.allocator.buffer(capacity: response.body.count)
            buffer.writeBytes(response.body)
            channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
            if !keepAlive {
                channel.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        reportAbandonedHandshake()
        context.close(promise: nil)
    }
}

/// Copies bytes one way between two channels; closes the peer when this side ends.
final class RelayHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let peer: Channel
    /// Sees every chunk that passes, e.g. to decode WebSocket frames.
    private let tap: (@Sendable (ByteBuffer) -> Void)?
    init(peer: Channel, tap: (@Sendable (ByteBuffer) -> Void)? = nil) {
        self.peer = peer; self.tap = tap
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        tap?(unwrapInboundIn(data))
        peer.writeAndFlush(data, promise: nil)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        peer.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
    }
}

/// Looks up the program behind a client connection once and remembers the answer for the connection's later requests.
final class ClientAppResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: String??

    func app(for channel: Channel) async -> String? {
        if let known = lock.withLock({ cached }) {
            return known
        }
        // A plain connection knows its peer itself; an HTTP/2 stream channel asks the connection it belongs to.
        let port = channel.remoteAddress?.port ?? channel.parent?.remoteAddress?.port
        let name = await Task.detached { port.flatMap { ClientProcess.name(forLocalPort: $0) } }.value
        lock.withLock { cached = .some(name) }
        return name
    }
}
