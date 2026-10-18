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
    let certificatePage: CertificatePage?
    /// The program behind a loopback client port, for attributing requests to apps.
    let clientApp: @Sendable (Int) -> String?
    /// The Mac's LAN addresses, so the certificate page also answers on them.
    let localAddresses: @Sendable () -> Set<String>
    let now: @Sendable () -> Date

    let upstream: UpstreamClients
    /// Where forwarded requests go; the upstream clients unless a test answers in their place.
    let sender: any UpstreamSending
    private let lock = NSLock()
    private var filter: HostFilter
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    private var mainListener: Channel?
    private var reverseListeners: [Channel] = []
    private var socksListener: Channel?
    private var serverCertificates: [CustomCertificateRule] = []
    private var preferHTTP2 = true
    private var accessControl = AccessControlSettings().compile()
    private var markModified = false
    /// Whether answers name the tools that changed them in `X-Watcher-Applied`.
    var marksModifiedTraffic: Bool {
        lock.withLock { markModified }
    }

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
        upstreamTLS: TLSConfiguration = .makeClientConfiguration(),
        upstream sender: (any UpstreamSending)? = nil,
        clientApp: @escaping @Sendable (Int) -> String? = ClientProcess.name(forLocalPort:),
        localAddresses: @escaping @Sendable () -> Set<String> = { Set(LocalNetwork.ipv4Addresses().map(\.ip)) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store; self.tools = tools; self.authority = authority; filter = sslProxying
        certificatePage = authority.map(CertificatePage.init)
        self.clientApp = clientApp; self.localAddresses = localAddresses; self.now = now
        upstream = UpstreamClients(group: group, tls: upstreamTLS)
        self.sender = sender ?? upstream
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
            preferHTTP2 = settings.preferHTTP2; accessControl = settings.accessControl.compile()
            autoIgnorePinning = settings.autoIgnoreSSLPinning; markModified = settings.markModifiedTraffic
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
            let channel = try await bind(host: host, port: settings.port) { [self] channel in
                channel.pipeline.addHandler(SocksHandler(server: self))
            }
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
        try await bind(host: host, port: port) { [self] channel in
            channel.pipeline.addHandlers(http1Pipeline(origin: origin).handlers)
        }
    }

    /// Accepts connections on `host:port` from the clients Access Control allows, each set up by `install`.
    private func bind(
        host: String,
        port: Int,
        install: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    ) async throws -> Channel {
        try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                guard allowsClient(channel) else {
                    channel.close(promise: nil)
                    return channel.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel)
                }
                return install(channel)
            }
            .bind(host: host, port: port).get()
    }

    func shouldIntercept(host: String) -> Bool {
        (authority != nil || hasCustomServerCertificate(for: host)) && sslProxying.allows(host)
    }
}

extension ProxyServer {
    static let hopByHop: Set<String> = [
        "connection", "keep-alive", "proxy-connection", "proxy-authenticate", "proxy-authorization",
        "te", "trailer", "transfer-encoding", "upgrade", "content-length",
    ]

    static func message(_ status: Int, _ text: String) -> ResponseRecord {
        ResponseRecord(status: status, headers: [Header("Content-Type", "text/plain; charset=utf-8")], body: Data(text.utf8))
    }

    /// Event streams, bodies of unknown length and very large bodies are relayed instead of buffered.
    static func shouldStream(_ response: HTTPClientResponse) -> Bool {
        // The client sees these as complete at the head, so a streamed end can race its close and fail the flow.
        let code = response.status.code
        if code < 200 || code == 204 || code == 304 {
            return false
        }
        if response.headers.first(name: "Content-Type")?.lowercased().contains("text/event-stream") == true {
            return true
        }
        guard let length = response.headers.first(name: "Content-Length") else { return true }
        return (Int(length) ?? 0) > maxBodyBytes / 8
    }
}
