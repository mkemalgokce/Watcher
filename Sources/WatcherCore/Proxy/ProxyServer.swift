import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1
import NIOSSL

public final class ProxyServer: @unchecked Sendable {
    public let store: FlowStore
    public let tools: ToolChain

    let authority: CertificateAuthority?
    /// Served for requests addressed to Watcher itself, so a device can download the root certificate.
    var certificatePage: CertificatePage? {
        authority.map(CertificatePage.init)
    }

    let upstream: UpstreamClients
    private let lock = NSLock()
    private var filter: HostFilter
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    private var mainListener: Channel?
    private var reverseListeners: [Channel] = []
    private var socksListener: Channel?
    private var serverCertificates: [CustomCertificateRule] = []
    private var preferHTTP2 = true
    private var accessControl = AccessControlSettings()
    private var markModified = false
    private var keyLog: KeyLogFile?
    private var keyLogPath = ""
    private var autoIgnorePinning = false
    private var reportedPinnedHosts: Set<String> = []
    /// Called (once per host) when a client abandons the TLS handshake with Watcher's certificate, which usually means pinning.
    var onPinningSuspected: (@Sendable (String) -> Void)?

    /// Largest body buffered whole, for the tools that must read it; bigger ones are streamed.
    static let maxBodyBytes = 64 * 1024 * 1024
    /// Uploads larger than this are streamed upstream instead of buffered.
    static let streamingUploadThreshold = maxBodyBytes / 8

    /// A request body still arriving from the client.
    struct Upload: Sendable {
        let body: AsyncStream<ByteBuffer>
        let length: Int
    }

    public init(
        store: FlowStore = FlowStore(),
        tools: ToolChain = ToolChain(),
        authority: CertificateAuthority?,
        sslProxying: HostFilter = HostFilter(),
        upstreamTLS: TLSConfiguration = .makeClientConfiguration()
    ) {
        self.store = store; self.tools = tools; self.authority = authority; filter = sslProxying
        upstream = UpstreamClients(group: group, tls: upstreamTLS)
    }

    public var sslProxying: HostFilter {
        get { lock.withLock { filter } }
        set { lock.withLock { filter = newValue } }
    }

    public func updateUpstream(external: ExternalProxySettings, pac: PACEvaluator?, dnsRules: [DNSSpoofRule], certificates: [CustomCertificateRule]) {
        upstream.update(external: external, pac: pac, dnsRules: dnsRules, clientCertificates: certificates.filter { $0.role == .client })
        lock.withLock { serverCertificates = certificates.filter { $0.role == .server } }
    }

    /// Applies the behaviour switches that can change while the proxy runs.
    public func updatePolicies(_ settings: WatcherSettings) {
        authority?.setLeafValidity(days: settings.leafCertificateValidityDays)
        let path = settings.tlsKeyLogFile.trimmingCharacters(in: .whitespaces)
        let sink: KeyLogFile? = lock.withLock { keyLogPath == path ? keyLog : nil }
        let activeSink = sink ?? (path.isEmpty ? nil : KeyLogFile(path: path))
        lock.withLock {
            preferHTTP2 = settings.preferHTTP2; accessControl = settings.accessControl; markModified = settings.markModifiedTraffic
            autoIgnorePinning = settings.autoIgnoreSSLPinning
            if keyLogPath != path {
                keyLog = activeSink; keyLogPath = path
            }
        }
        authority?.setKeyLog(activeSink?.callback)
        upstream.setKeyLog(activeSink?.callback)
    }

    func allowsClient(_ channel: Channel) -> Bool {
        lock.withLock { accessControl }.allows(channel.remoteAddress?.ipAddress)
    }

    /// A client closed or failed the handshake on a decrypted connection; with auto-ignore on, the host stops being decrypted.
    func handshakeFailed(host: String) {
        let report: Bool = lock.withLock { autoIgnorePinning && reportedPinnedHosts.insert(host).inserted }
        if report {
            onPinningSuspected?(host)
        }
    }

    private func customServerCertificate(for host: String) -> CustomCertificateRule? {
        lock.withLock { serverCertificates.first { Wildcard($0.host).matches(host) } }
    }

    func hasCustomServerCertificate(for host: String) -> Bool {
        customServerCertificate(for: host) != nil
    }

    /// The certificate presented to a client for `host`: the user's own P12 identity if a rule covers it, else one signed by the Watcher CA.
    func serverContext(for host: String) throws -> NIOSSLContext {
        let (offerHTTP2, sink) = lock.withLock { (preferHTTP2, keyLog) }
        if let rule = customServerCertificate(for: host) {
            return try CustomCertificates.serverContext(rule, offerHTTP2: offerHTTP2, keyLog: sink?.callback)
        }
        guard let authority else { throw CertificateAuthority.Unavailable() }
        return try authority.serverContext(for: host, offerHTTP2: offerHTTP2)
    }

    /// Address to dial for `host`, after DNS Spoofing; used by tunnels, which bypass the HTTP client.
    func resolve(_ host: String) -> String {
        upstream.address(for: host)
    }

    /// Starts the main proxy listener and returns the bound port (useful with port 0).
    @discardableResult
    public func start(host: String = "127.0.0.1", port: Int) async throws -> Int {
        let channel = try await listen(host: host, port: port, origin: nil)
        lock.withLock { mainListener = channel }
        return channel.localAddress?.port ?? port
    }

    /// Replaces the reverse-proxy listeners; returns a message for each one that could not start.
    public func setReverseProxies(_ rules: [ReverseProxyRule]) async -> [String] {
        let old = lock.withLock { defer { reverseListeners = [] }; return reverseListeners }
        for channel in old {
            try? await channel.close()
        }

        var failures: [String] = []
        var started: [Channel] = []
        for rule in rules {
            let origin = ReverseOrigin(
                scheme: rule.usesTLS ? "https" : "http",
                host: rule.remoteHost,
                port: rule.remotePort,
                preserveHost: rule.preserveHost
            )
            do { try await started.append(listen(host: "127.0.0.1", port: rule.localPort, origin: origin)) }
            catch { failures.append("Reverse proxy on port \(rule.localPort): \(error)") }
        }
        lock.withLock { reverseListeners = started }
        return failures
    }

    /// Starts, moves or stops the SOCKS5 listener; returns a message if it could not start.
    public func setSocks(_ settings: SocksSettings, host: String) async -> String? {
        if let old = lock.withLock({ defer { socksListener = nil }; return socksListener }) {
            try? await old.close()
        }
        guard settings.isEnabled else { return nil }
        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { [self] channel in
                    guard allowsClient(channel) else { channel.close(promise: nil); return channel.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel) }
                    return channel.pipeline.addHandler(SocksHandler(server: self))
                }
                .bind(host: host, port: settings.port).get()
            lock.withLock { socksListener = channel }
            return nil
        } catch { return "SOCKS proxy on port \(settings.port): \(error)" }
    }

    public func stop() async throws {
        let channels = lock.withLock { defer { mainListener = nil; reverseListeners = []; socksListener = nil }; return [mainListener, socksListener].compactMap(\.self) + reverseListeners }
        for channel in channels {
            try? await channel.close()
        }
        await upstream.shutdown()
        try await group.shutdownGracefully()
    }

    private func listen(host: String, port: Int, origin: ReverseOrigin?) async throws -> Channel {
        try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                guard allowsClient(channel) else { channel.close(promise: nil); return channel.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel) }
                let encoder = HTTPResponseEncoder()
                let decoder = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                let handler = ProxyConnectionHandler(server: self, codecs: [encoder, decoder], origin: origin)
                return channel.pipeline.addHandlers([encoder, decoder, handler])
            }
            .bind(host: host, port: port).get()
    }

    func shouldIntercept(host: String) -> Bool {
        (authority != nil || hasCustomServerCertificate(for: host)) && sslProxying.allows(host)
    }

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
        guard case let .buffered(response) = await serve(original, allowStreaming: false, upload: nil, timeout: timeout) else { fatalError("streaming was not allowed") }
        return response
    }

    func serve(_ original: RequestRecord, allowStreaming: Bool, upload: Upload? = nil, connection: String? = nil, timeout: Int = 60) async -> ClientResponse {
        var request = original
        let flow = store.begin(request)
        if let connection {
            store.update(flow.id) { $0.clientTLS = connection }
        }
        let started = Date()

        let markTools = lock.withLock { markModified }
        func marked(_ response: ResponseRecord, _ tools: [String]) -> ResponseRecord {
            guard markTools, !tools.isEmpty else { return response }
            var copy = response
            copy.headers.set("X-Watcher-Applied", tools.joined(separator: ", "))
            return copy
        }

        func finish(_ response: ResponseRecord, state: Flow.State, tools: [String], error: String? = nil) -> ClientResponse {
            let response = marked(response, tools)
            store.update(flow.id) {
                $0.request = request; $0.response = response; $0.state = state
                $0.error = error; $0.appliedTools = tools
                $0.duration = Date().timeIntervalSince(started)
            }
            return .buffered(response)
        }

        let (decision, requestTools) = await tools.applyRequest(&request)
        switch decision {
        case let .block(hidden):
            if hidden {
                store.discard(flow.id)
            }
            return finish(Self.message(403, "Blocked by Watcher"), state: .blocked, tools: requestTools)
        case let .respond(response):
            return finish(response, state: .completed, tools: requestTools)
        case .forward:
            do {
                let sentAt = Date()
                let upstreamResponse = try await send(request, upload: upload, timeout: timeout)
                let firstByte = Date().timeIntervalSince(sentAt)
                let version = upstreamResponse.version.major == 2 ? "HTTP/2" : "HTTP/\(upstreamResponse.version.major).\(upstreamResponse.version.minor)"
                store.update(flow.id) { $0.timeToFirstByte = firstByte; $0.upstreamHTTPVersion = version }
                var head = ResponseRecord(
                    status: Int(upstreamResponse.status.code),
                    headers: upstreamResponse.headers.compactMap { Self.hopByHop.contains($0.name.lowercased()) ? nil : Header($0.name, $0.value) }
                )

                if allowStreaming, !tools.inspectsResponses, Self.shouldStream(upstreamResponse) {
                    head = marked(head, requestTools)
                    store.update(flow.id) { $0.request = request; $0.response = head; $0.appliedTools = requestTools }
                    return .streamed(head: head, body: upstreamResponse.body) { [store] captured, error in
                        store.update(flow.id) {
                            $0.response?.body = captured
                            $0.state = error == nil ? .completed : .failed
                            $0.error = error.map { "\($0)" }
                            $0.duration = Date().timeIntervalSince(started)
                        }
                    }
                }

                var body = try await upstreamResponse.body.collect(upTo: Self.maxBodyBytes)
                var response = head
                response.body = Data(body.readBytes(length: body.readableBytes) ?? [])
                let responseTools = await tools.applyResponse(&response, for: request)
                return finish(response, state: .completed, tools: requestTools + responseTools)
            } catch {
                return finish(
                    Self.message(502, "Watcher could not reach \(request.host): \(error)"),
                    state: .failed,
                    tools: requestTools,
                    error: "\(error)"
                )
            }
        }
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
        return try await upstream.client(for: request).execute(upstreamRequest, timeout: .seconds(Int64(max(1, timeout))))
    }

    /// Event streams, bodies of unknown length and very large bodies are relayed instead of buffered.
    private static func shouldStream(_ response: HTTPClientResponse) -> Bool {
        if response.headers.first(name: "Content-Type")?.lowercased().contains("text/event-stream") == true {
            return true
        }
        guard let length = response.headers.first(name: "Content-Length") else { return true }
        return (Int(length) ?? 0) > maxBodyBytes / 8
    }

    static let hopByHop: Set<String> = [
        "connection", "keep-alive", "proxy-connection", "proxy-authenticate", "proxy-authorization",
        "te", "trailer", "transfer-encoding", "upgrade", "content-length",
    ]

    static func message(_ status: Int, _ text: String) -> ResponseRecord {
        ResponseRecord(status: status, headers: [Header("Content-Type", "text/plain; charset=utf-8")], body: Data(text.utf8))
    }
}
