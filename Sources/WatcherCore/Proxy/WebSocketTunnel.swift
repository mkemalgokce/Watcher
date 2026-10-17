import Foundation
import NIO
import NIOSSL

/// WebSocket (any `Upgrade`) support: the handshake is recorded, then bytes are relayed untouched in both directions.
extension ProxyServer {
    enum UpgradeOutcome {
        case tunnel(RequestRecord, Flow.ID)
        case answer(ResponseRecord)
    }

    /// Records the handshake and lets Block/Allow/Map tools decide whether it may proceed.
    func prepareUpgrade(_ original: RequestRecord) async -> UpgradeOutcome {
        var request = original
        let flow = store.begin(request)
        let (decision, applied) = await tools.applyRequest(&request)
        switch decision {
        case .forward:
            store.update(flow.id) { $0.request = request; $0.appliedTools = applied }
            return .tunnel(request, flow.id)
        case let .block(hidden):
            if hidden {
                store.discard(flow.id)
            }
            return .answer(finishUpgrade(flow.id, status: 403, message: "Blocked by Watcher", state: .blocked))
        case let .respond(response):
            store.update(flow.id) { $0.response = response; $0.state = .completed; $0.appliedTools = applied }
            return .answer(response)
        }
    }

    /// Opens the upstream connection (TLS for `https`/`wss`) and relays its bytes to `client`; the handshake is sent separately.
    func connectUpgrade(_ request: RequestRecord, on loop: EventLoop, client: Channel, recorder: WebSocketRecorder) async throws -> Channel {
        let tls = upstream.tls
        return try await ClientBootstrap(group: loop)
            .channelInitializer { channel in
                do {
                    if request.scheme == "https" {
                        let context = try NIOSSLContext(configuration: tls)
                        try channel.pipeline.syncOperations.addHandler(NIOSSLClientHandler(context: context, serverHostname: request.host))
                    }
                    try channel.pipeline.syncOperations.addHandler(RelayHandler(peer: client, tap: { recorder.record($0, direction: .serverToClient) }))
                    return channel.eventLoop.makeSucceededVoidFuture()
                } catch { return channel.eventLoop.makeFailedFuture(error) }
            }
            .connect(host: resolve(request.host), port: request.port).get()
    }

    static func handshakeBytes(for request: RequestRecord, allocator: ByteBufferAllocator) -> ByteBuffer {
        var head = "\(request.method) \(request.path) HTTP/1.1\r\n"
        for header in request.headers where header.name.lowercased() != "proxy-connection" {
            head += "\(header.name): \(header.value)\r\n"
        }
        head += "\r\n"
        return allocator.buffer(string: head)
    }

    @discardableResult
    func finishUpgrade(_ id: Flow.ID, status: Int, message: String? = nil, state: Flow.State = .completed, error: String? = nil) -> ResponseRecord {
        let response = message.map { Self.message(status, $0) }
            ?? ResponseRecord(status: status, headers: [Header("Upgrade", "websocket")])
        store.update(id) { $0.response = response; $0.state = state; $0.error = error }
        return response
    }
}
