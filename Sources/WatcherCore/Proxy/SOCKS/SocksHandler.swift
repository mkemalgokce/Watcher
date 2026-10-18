import Foundation
import NIO
import NIOHTTP1
import NIOSSL

/// SOCKS5 front door (no authentication, CONNECT only). After the handshake the connection is treated like an HTTP CONNECT tunnel.
final class SocksHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State { case greeting, request, awaitingPayload(host: String, port: Int) }

    private let server: ProxyServer
    private var state = State.greeting
    private var pending = [UInt8]()

    init(server: ProxyServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        pending += incoming.readBytes(length: incoming.readableBytes) ?? []
        advance(context)
    }

    private func advance(_ context: ChannelHandlerContext) {
        switch state {
        case .greeting:
            guard pending.count >= 2 else { return }
            guard pending[0] == 5, pending.count >= 2 + Int(pending[1]) else { return pending[0] == 5 ? () : context.close(promise: nil) }
            let methods = pending[2 ..< (2 + Int(pending[1]))]
            pending.removeFirst(2 + Int(pending[1]))
            guard methods.contains(0) else { reply(context, [5, 0xFF]); return context.close(promise: nil) }
            reply(context, [5, 0])
            state = .request
            advance(context)
        case .request:
            guard let (host, port, consumed) = parseRequest() else { return }
            if consumed < 0 {
                reply(context, [5, 7, 0, 1, 0, 0, 0, 0, 0, 0]); return context.close(promise: nil)
            }
            pending.removeFirst(consumed)
            if server.shouldIntercept(host: host) {
                reply(context, Self.success)
                state = .awaitingPayload(host: host, port: port)
                advance(context)
            } else {
                relay(context, host: host, port: port)
            }
        case let .awaitingPayload(host, port):
            guard let first = pending.first else { return }
            install(context, host: host, port: port, isTLS: first == 0x16)
        }
    }

    /// Returns host, port and bytes consumed; consumed < 0 means unsupported; nil means more bytes are needed.
    private func parseRequest() -> (String, Int, Int)? {
        guard pending.count >= 4 else { return nil }
        guard pending[0] == 5, pending[1] == 1 else { return ("", 0, -1) }
        let host: String, addressEnd: Int
        switch pending[3] {
        case 1:
            guard pending.count >= 10 else { return nil }
            host = pending[4 ..< 8].map(String.init).joined(separator: "."); addressEnd = 8
        case 3:
            guard pending.count >= 5, pending.count >= 7 + Int(pending[4]) else { return nil }
            host = String(decoding: pending[5 ..< (5 + Int(pending[4]))], as: UTF8.self); addressEnd = 5 + Int(pending[4])
        case 4:
            guard pending.count >= 22 else { return nil }
            host = stride(from: 4, to: 20, by: 2).map { String(format: "%x", Int(pending[$0]) << 8 | Int(pending[$0 + 1])) }.joined(separator: ":"); addressEnd = 20
        default: return ("", 0, -1)
        }
        return (host, Int(pending[addressEnd]) << 8 | Int(pending[addressEnd + 1]), addressEnd + 2)
    }

    private static let success: [UInt8] = [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]

    private func reply(_ context: ChannelHandlerContext, _ bytes: [UInt8]) {
        context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(bytes: bytes)), promise: nil)
    }

    /// Hosts we do not decrypt: connect first so a failure can still be reported, then relay bytes untouched.
    private func relay(_ context: ChannelHandlerContext, host: String, port: Int) {
        let client = context.channel
        let leftover = pending; pending = []
        server.connectBlind(to: host, port: port, on: context.eventLoop).whenComplete { [self] result in
            switch result {
            case .failure:
                reply(context, [5, 5, 0, 1, 0, 0, 0, 0, 0, 0]); context.close(promise: nil)
            case let .success(upstream):
                reply(context, Self.success)
                RelayHandler.join(client, upstream)
                    .flatMap { context.pipeline.removeHandler(self) }
                    .whenComplete { _ in
                        if !leftover.isEmpty {
                            upstream.writeAndFlush(upstream.allocator.buffer(bytes: leftover), promise: nil)
                        }
                    }
            }
        }
    }

    /// Swaps this handler for the HTTP pipeline (with TLS first when the client starts a handshake) and replays the buffered bytes.
    private func install(_ context: ChannelHandlerContext, host: String, port: Int, isTLS: Bool) {
        let replay = context.channel.allocator.buffer(bytes: pending)
        pending = []
        let pipeline = context.pipeline
        do {
            let details = ConnectionDetails()
            let tunnel = TunnelTarget(scheme: isTLS ? "https" : "http", host: host, port: port)
            let http1 = server.http1Pipeline(tunnel: tunnel, details: details)
            var handlers: [ChannelHandler] = http1.handlers
            if isTLS, server.authority != nil {
                let tls = try server.tlsHandlers(host: host, http1: http1.handlers, details: details)
                handlers.insert(contentsOf: tls, at: 0)
            }
            pipeline.addHandlers(handlers, position: .first)
                .flatMap { pipeline.removeHandler(self) }
                .whenComplete { result in
                    if case .success = result {
                        pipeline.fireChannelRead(NIOAny(replay))
                    } else {
                        context.close(promise: nil)
                    }
                }
        } catch {
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
    }
}
