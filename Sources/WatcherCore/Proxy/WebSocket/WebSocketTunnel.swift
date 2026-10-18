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
        let flowID = store.begin(request).id
        let exchange = FlowExchange(store: store, flowID: flowID, marksTools: marksModifiedTraffic, now: now)
        let (decision, applied) = await tools.applyRequest(&request)
        if let answer = exchange.answer(decision, to: request, tools: applied) {
            return .answer(answer)
        }
        store.update(exchange.flowID) { $0.request = request; $0.appliedTools = applied }
        return .tunnel(request, exchange.flowID)
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
