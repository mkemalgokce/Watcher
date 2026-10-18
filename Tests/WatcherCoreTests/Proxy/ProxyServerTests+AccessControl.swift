import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    /// Whether a connecting peer may use the proxy, judged by its address.
    @Suite(.tags(.unit), .timeLimit(.minutes(1)))
    struct AccessControl {
        private func server(allowing patterns: [String]) -> ProxyServer {
            let server = ProxyServer(authority: nil)
            var settings = WatcherSettings()
            settings.accessControl = AccessControlSettings(isEnabled: true, allowedAddresses: patterns)
            server.updatePolicies(settings)
            return server
        }

        private func peer(_ address: String) async throws -> NIOAsyncTestingChannel {
            let channel = NIOAsyncTestingChannel()
            try await channel.connect(to: SocketAddress(ipAddress: address, port: 50000)).get()
            return channel
        }

        @Test(arguments: [
            ("127.0.0.1", [], true), ("::1", [], true), ("192.168.1.9", [], false),
            ("192.168.1.9", ["192.168.1.*"], true), ("10.0.0.2", ["192.168.1.*"], false),
            ("::ffff:192.168.1.9", ["192.168.1.*"], true), ("::ffff:192.168.1.9", [], false),
        ] as [(String, [String], Bool)])
        func aPeerIsAllowedByItsAddress(address: String, patterns: [String], allowed: Bool) async throws {
            let server = server(allowing: patterns)
            #expect(try await server.allowsClient(peer(address)) == allowed)
        }

        @Test
        func aPeerWithoutAnAddressIsRefused() {
            #expect(!server(allowing: ["*"]).allowsClient(NIOAsyncTestingChannel()))
        }
    }
}
