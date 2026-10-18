import NIO
import NIOHTTP1

/// Answers `/redirect`, `/notmodified`, HEAD and the bodiless paths specially, delays `/slow`, and echoes everything else.
final class EchoHandler: ChannelInboundHandler {
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
            respond(to: head, context: context)
        }
    }

    private func respond(to head: HTTPRequestHead, context: ChannelHandlerContext) {
        if head.uri == "/redirect" {
            return sendHead(context, .found, ["Location": "/final", "Content-Length": "0"])
        }
        // No body although a length is announced: HEAD and 304 describe a body they do not send.
        if head.method == .HEAD || head.uri == "/notmodified" {
            let status: HTTPResponseStatus = head.method == .HEAD ? .ok : .notModified
            return sendHead(context, status, ["Content-Length": "42", "ETag": "\"v1\""])
        }
        // Bodiless answers: a declared zero length, a 204, and an empty body ended by closing the connection.
        if ["/empty", "/nocontent", "/close"].contains(head.uri) {
            return sendBodiless(to: head.uri, context: context)
        }
        if head.uri == "/slow" {
            return respondAfterDelay(to: head, context: context)
        }
        sendEcho(of: head, context: context)
    }

    private func respondAfterDelay(to head: HTTPRequestHead, context: ChannelHandlerContext) {
        context.eventLoop.scheduleTask(in: .milliseconds(300)) { self.sendEcho(of: head, context: context) }
    }

    private func sendBodiless(to uri: String, context: ChannelHandlerContext) {
        let status: HTTPResponseStatus = uri == "/nocontent" ? .noContent : .ok
        let headers: HTTPHeaders = switch uri {
        case "/empty": ["Content-Length": "0"]
        case "/close": ["Connection": "close"]
        default: [:]
        }
        writeHead(context, status, headers)
        let done = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        if uri == "/close" {
            done.whenComplete { _ in context.close(promise: nil) }
        }
    }

    private func sendEcho(of head: HTTPRequestHead, context: ChannelHandlerContext) {
        let host = head.headers.first(name: "Host") ?? "-"
        let script = head.headers.first(name: "X-Script") ?? "-"
        let text = "\(head.method.rawValue) \(head.uri) host=\(host) script=\(script) bytes=\(receivedBytes)"
        var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let headers: HTTPHeaders = ["Content-Length": "\(buffer.readableBytes)", "Content-Type": "text/plain"]
        writeHead(context, .ok, headers)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func sendHead(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus, _ headers: HTTPHeaders) {
        writeHead(context, status, headers)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func writeHead(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus, _ headers: HTTPHeaders) {
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
    }
}
