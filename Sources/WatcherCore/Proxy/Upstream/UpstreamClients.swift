import AsyncHTTPClient
import Foundation
import NIO
import NIOSSL

/// Hands out HTTP clients for upstream requests, honouring the external proxy (static or PAC) and DNS spoofing settings.
final class UpstreamClients: @unchecked Sendable {
    private let group: EventLoopGroup
    let tls: TLSConfiguration
    private let lock = NSLock()
    private var external = ExternalProxySettings()
    private var bypass = HostList([])
    private var pac: PACEvaluator?
    private var spoofs: [DNSSpoofRule] = []
    private var clientCertificates: [CustomCertificateRule] = []
    private var keyLog: NIOSSLKeyLogCallback?
    private var cache: [String: HTTPClient] = [:]

    init(group: EventLoopGroup, tls: TLSConfiguration) {
        self.group = group; self.tls = tls
    }

    func update(external: ExternalProxySettings, pac: PACEvaluator?, dnsRules: [DNSSpoofRule], clientCertificates: [CustomCertificateRule]) {
        let stale: [HTTPClient] = lock.withLock {
            self.external = external; self.pac = pac
            bypass = HostList(["localhost", "127.0.0.1", "::1"] + external.bypass)
            spoofs = dnsRules; self.clientCertificates = clientCertificates
            defer { cache.removeAll() }
            return Array(cache.values)
        }
        for client in stale {
            Task { try? await client.shutdown() }
        }
    }

    func setKeyLog(_ callback: NIOSSLKeyLogCallback?) {
        let stale: [HTTPClient] = lock.withLock { keyLog = callback; defer { cache.removeAll() }; return Array(cache.values) }
        for client in stale {
            Task { try? await client.shutdown() }
        }
    }

    /// The address to connect to for `host`: a spoofed one if a DNS Spoofing rule matches, else the host itself.
    func address(for host: String) -> String {
        lock.withLock { spoofs.first { $0.host.caseInsensitiveCompare(host) == .orderedSame }?.address ?? host }
    }

    func client(for request: RequestRecord) -> HTTPClient {
        lock.withLock {
            let host = request.host
            let address = spoofs.first { $0.host.caseInsensitiveCompare(host) == .orderedSame }?.address
            let route = routeLocked(for: request)
            let identity = clientCertificates.first { Wildcard($0.host).matches(host) }
            let key = "\(host)|\(address ?? "-")|\(route)|\(identity?.p12Path ?? "-")"
            if let existing = cache[key] {
                return existing
            }

            var tlsConfiguration = tls
            tlsConfiguration.keyLogCallback = keyLog
            // shortcut: an unreadable P12 silently falls back to no client identity; surface it through a log hook if that bites.
            if let identity {
                try? CustomCertificates.applyClientIdentity(identity, to: &tlsConfiguration)
            }
            var configuration = HTTPClient.Configuration(tlsConfiguration: tlsConfiguration, redirectConfiguration: .disallow)
            configuration.timeout = .init(connect: .seconds(15), read: .seconds(60))
            if let address {
                configuration.dnsOverride = [host: address]
            }
            switch route {
            case .direct: break
            case let .http(proxyHost, proxyPort):
                let credentials = external.kind == .http && !external.username.isEmpty
                    ? HTTPClient.Authorization.basic(username: external.username, password: external.password) : nil
                configuration.proxy = .server(host: proxyHost, port: proxyPort, authorization: credentials)
            case let .socks(proxyHost, proxyPort):
                configuration.proxy = .socksServer(host: proxyHost, port: proxyPort)
            }
            let client = HTTPClient(eventLoopGroupProvider: .shared(group), configuration: configuration)
            cache[key] = client
            return client
        }
    }

    func shutdown() async {
        let clients = lock.withLock { defer { cache.removeAll() }; return Array(cache.values) }
        for client in clients {
            try? await client.shutdown()
        }
    }

    private func routeLocked(for request: RequestRecord) -> PACEvaluator.Route {
        guard external.isEnabled, !bypass.matches(request.host) else { return .direct }
        switch external.kind {
        case .http: return .http(host: external.host, port: external.port)
        case .socks: return .socks(host: external.host, port: external.port)
        case .pac: return pac?.route(for: request.url, host: request.host) ?? .direct
        }
    }
}
