import Foundation
import NIO
import NIOSSL
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct UpstreamClientsTests {
    private static let proxy = ExternalProxySettings(isEnabled: true, kind: .http, host: "proxy.test", port: 3128)

    /// Runs `body` against clients configured with `external`, then shuts every client and thread down.
    private func withClients(
        external: ExternalProxySettings = ExternalProxySettings(),
        pac: PACEvaluator? = nil,
        dnsRules: [DNSSpoofRule] = [],
        _ body: (UpstreamClients) throws -> Void
    ) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clients = UpstreamClients(group: group, tls: .makeClientConfiguration())
        clients.update(external: external, pac: pac, dnsRules: dnsRules, clientCertificates: [])
        do { try body(clients) } catch {
            await clients.shutdown(); try await group.shutdownGracefully()
            throw error
        }
        await clients.shutdown(); try await group.shutdownGracefully()
    }

    @Test(arguments: [("API.test", "10.0.0.1"), ("api.test", "10.0.0.1"), ("other.test", "other.test")])
    func aSpoofedHostResolvesToItsAddressWhateverItsCase(host: String, address: String) async throws {
        try await withClients(dnsRules: [DNSSpoofRule(host: "api.test", address: "10.0.0.1")]) { clients in
            #expect(clients.address(for: host) == address)
        }
    }

    @Test
    func aDisabledExternalProxySendsEverythingDirect() async throws {
        try await withClients { clients in
            #expect(clients.route(for: .fixture(host: "a.test")) == .direct)
        }
    }

    @Test(arguments: [
        ("a.test", PACEvaluator.Route.http(host: "proxy.test", port: 3128)),
        ("localhost", .direct), ("127.0.0.1", .direct), ("::1", .direct), ("intranet.test", .direct),
    ])
    func theProxyCarriesEveryHostButLocalAndBypassedOnes(host: String, route: PACEvaluator.Route) async throws {
        var external = Self.proxy; external.bypass = ["intranet.test"]
        try await withClients(external: external) { clients in
            #expect(clients.route(for: .fixture(host: host)) == route)
        }
    }

    @Test
    func aSocksProxyIsUsedAsSuch() async throws {
        var external = Self.proxy; external.kind = .socks
        try await withClients(external: external) { clients in
            #expect(clients.route(for: .fixture(host: "a.test")) == .socks(host: "proxy.test", port: 3128))
        }
    }

    @Test
    func aPACSettingFollowsTheScriptAndGoesDirectWithoutOne() async throws {
        var external = Self.proxy; external.kind = .pac
        let pac = try PACEvaluator(script: "function FindProxyForURL() { return 'SOCKS s.test:1080'; }")
        try await withClients(external: external, pac: pac) { clients in
            #expect(clients.route(for: .fixture(host: "a.test")) == .socks(host: "s.test", port: 1080))
        }
        try await withClients(external: external) { clients in
            #expect(clients.route(for: .fixture(host: "a.test")) == .direct)
        }
    }

    @Test
    func aHostKeepsItsClientUntilTheSettingsChange() async throws {
        try await withClients { clients in
            let first = clients.client(for: .fixture(host: "a.test"))
            #expect(clients.client(for: .fixture(host: "a.test")) === first)
            #expect(clients.client(for: .fixture(host: "b.test")) !== first)
            clients.update(external: Self.proxy, pac: nil, dnsRules: [], clientCertificates: [])
            #expect(clients.client(for: .fixture(host: "a.test")) !== first)
        }
    }

    @Test
    func aNewKeyLogReplacesTheCachedClients() async throws {
        try await withClients { clients in
            let first = clients.client(for: .fixture(host: "a.test"))
            clients.setKeyLog(nil)
            #expect(clients.client(for: .fixture(host: "a.test")) !== first)
        }
    }
}
