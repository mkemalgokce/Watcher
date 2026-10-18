import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1

/// Writes Watcher's answers to a client, whole or streamed, with only the connection headers the protocol allows.
struct ResponseWriter {
    /// An HTTP/2 stream has no connection of its own to keep alive or close.
    let isHTTP2: Bool

    private func keepAlive(_ head: HTTPRequestHead) -> Bool {
        isHTTP2 || head.isKeepAlive
    }

    /// Relays the upstream body as it arrives (chunked), keeping a bounded copy for the session list.
    func stream(
        _ response: ResponseRecord,
        body: HTTPClientResponse.Body,
        to channel: Channel,
        head: HTTPRequestHead,
        complete: @Sendable (Data, Error?) -> Void
    ) async {
        var captured = Data()
        do {
            let responseHead = responseHead(response, bodyLength: nil, keepAlive: keepAlive(head))
            try await channel.writeAndFlush(HTTPServerResponsePart.head(responseHead))
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

    /// A plain-text answer Watcher makes up itself, such as an error.
    func respond(_ status: Int, _ text: String, to channel: Channel, head: HTTPRequestHead) {
        respond(ProxyServer.message(status, text), to: channel, head: head)
    }

    func respond(_ response: ResponseRecord, to channel: Channel, head: HTTPRequestHead) {
        let keepAlive = keepAlive(head)
        let responseHead = responseHead(response, bodyLength: response.body.count, keepAlive: keepAlive)
        channel.write(HTTPServerResponsePart.head(responseHead), promise: nil)
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
}
