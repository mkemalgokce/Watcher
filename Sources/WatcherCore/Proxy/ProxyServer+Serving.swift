import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1

/// One request's trip through the proxy: recorded, run through the tools, sent upstream and answered.
extension ProxyServer {
    /// What the connection handler should write back.
    enum ClientResponse {
        case buffered(ResponseRecord)
        /// Body is relayed chunk by chunk; `complete` receives the captured prefix and any error when it ends.
        case streamed(head: ResponseRecord, body: HTTPClientResponse.Body, complete: @Sendable (Data, Error?) -> Void)
    }

    /// shortcut: only this many bytes of a streamed body are kept in the session list.
    static let maxCapturedStreamBytes = 1024 * 1024

    /// Records the request, runs the tools, forwards upstream and returns the whole response (used by Compose).
    public func process(_ original: RequestRecord, timeout: Int = 60) async -> ResponseRecord {
        guard case let .buffered(response) = await serve(original, allowStreaming: false, timeout: timeout) else {
            fatalError("streaming was not allowed")
        }
        return response
    }

    func serve(
        _ original: RequestRecord,
        allowStreaming: Bool,
        upload: Upload? = nil,
        connection: String? = nil,
        timeout: Int = 60
    ) async -> ClientResponse {
        var request = original
        let flowID = store.begin(request).id
        let exchange = FlowExchange(store: store, flowID: flowID, marksTools: marksModifiedTraffic, now: now)
        if let connection {
            store.update(exchange.flowID) { $0.clientTLS = connection }
        }
        let (decision, requestTools) = await tools.applyRequest(&request)
        switch decision {
        case let .block(hidden):
            if hidden {
                store.discard(exchange.flowID)
            }
            let blocked = Self.message(403, "Blocked by Watcher")
            return exchange.finish(request, blocked, state: .blocked, tools: requestTools)
        case let .respond(response):
            return exchange.finish(request, response, state: .completed, tools: requestTools)
        case .forward:
            do {
                let sending = Sending(request: request, upload: upload, timeout: timeout)
                return try await forward(
                    sending, allowStreaming: allowStreaming, exchange: exchange, tools: requestTools
                )
            } catch {
                let failure = Self.message(502, "Watcher could not reach \(request.host): \(error)")
                return exchange.finish(request, failure, state: .failed, tools: requestTools, error: "\(error)")
            }
        }
    }

    /// A request the tools let through, with how it may travel.
    private struct Sending {
        let request: RequestRecord
        let upload: Upload?
        let timeout: Int
    }

    private func forward(
        _ sending: Sending,
        allowStreaming: Bool,
        exchange: FlowExchange,
        tools requestTools: [String]
    ) async throws -> ClientResponse {
        let request = sending.request
        let sentAt = now()
        let upstreamResponse = try await send(request, upload: sending.upload, timeout: sending.timeout)
        let firstByte = now().timeIntervalSince(sentAt)
        store.update(exchange.flowID) {
            $0.timeToFirstByte = firstByte; $0.upstreamHTTPVersion = Self.versionName(upstreamResponse.version)
        }
        let head = ResponseRecord(
            status: Int(upstreamResponse.status.code),
            headers: upstreamResponse.headers.compactMap {
                Self.hopByHop.contains($0.name.lowercased()) ? nil : Header($0.name, $0.value)
            }
        )
        if allowStreaming, !tools.inspectsResponses, Self.shouldStream(upstreamResponse) {
            return exchange.stream(request, head: head, body: upstreamResponse.body, tools: requestTools)
        }
        var body = try await upstreamResponse.body.collect(upTo: Self.maxBodyBytes)
        var response = head
        response.body = Data(body.readBytes(length: body.readableBytes) ?? [])
        let responseTools = await tools.applyResponse(&response, for: request)
        return exchange.finish(request, response, state: .completed, tools: requestTools + responseTools)
    }

    private static func versionName(_ version: HTTPVersion) -> String {
        version.major == 2 ? "HTTP/2" : "HTTP/\(version.major).\(version.minor)"
    }

    private func send(_ request: RequestRecord, upload: Upload?, timeout: Int) async throws -> HTTPClientResponse {
        var upstreamRequest = HTTPClientRequest(url: request.url)
        upstreamRequest.method = .init(rawValue: request.method)
        for header in request.headers where !Self.hopByHop.contains(header.name.lowercased()) {
            upstreamRequest.headers.add(name: header.name, value: header.value)
        }
        if let upload {
            upstreamRequest.body = .stream(upload.body, length: .known(Int64(upload.length)))
        } else if !request.body.isEmpty {
            upstreamRequest.body = .bytes(request.body)
        }
        return try await sender.execute(upstreamRequest, for: request, timeout: .seconds(Int64(max(1, timeout))))
    }
}
