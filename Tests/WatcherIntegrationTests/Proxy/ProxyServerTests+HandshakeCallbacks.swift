import AsyncHTTPClient
import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    /// The callbacks a caller installs before `start` are what the very first connection reports to: the server reads
    /// them under its lock, so nothing the caller set up first can be missed. The callbacks record into boxes the
    /// test polls, so a callback that fires before the wait starts is never lost and one that never fires fails fast.
    @Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
    struct HandshakeCallbacks {
        private func firstRejectedHandshake(
            autoIgnore: Bool
        ) async throws -> (abandoned: [String], suspected: [String]) {
            let authority = try CertificateAuthority(
                directory: URL(fileURLWithPath: "/watcher-ca"), files: FileAccessFake().access
            )
            let server = ProxyServer(authority: authority, clientApp: { _ in nil })
            var settings = WatcherSettings()
            settings.autoIgnoreSSLPinning = autoIgnore
            server.updatePolicies(settings)
            let abandoned = LockedBox<[String]>([])
            let suspected = LockedBox<[String]>([])
            server.onHandshakeAbandoned = { host in abandoned.mutate { $0.append(host) } }
            server.onPinningSuspected = { host in suspected.mutate { $0.append(host) } }
            let port = try await server.start(port: 0)

            // A client that trusts another authority than Watcher's walks away from the first handshake.
            let client = try HTTPClient(
                eventLoopGroupProvider: .singleton,
                configuration: HTTPClient.Configuration(
                    tlsConfiguration: OriginAuthority().trust, proxy: .server(host: "127.0.0.1", port: port)
                )
            )
            let pinned = HTTPClientRequest(url: "https://pinned.test/")
            let request = Task { try? await client.execute(pinned, timeout: .seconds(10)) }
            let reported = await eventually(timeout: 20, poll: .milliseconds(50)) {
                !abandoned.value.isEmpty && (!autoIgnore || !suspected.value.isEmpty)
            }
            #expect(reported, "the handshake callbacks never fired")
            request.cancel()
            try? await client.shutdown()
            try await server.stop()
            return (abandoned.value, suspected.value)
        }

        @Test
        func theAbandonedHandshakeCallbackSeesTheFirstConnection() async throws {
            let seen = try await firstRejectedHandshake(autoIgnore: false)
            #expect(seen.abandoned.first == "pinned.test")
            #expect(seen.suspected.isEmpty, "pinning is only suspected while auto-ignore is on")
        }

        @Test
        func thePinningCallbackSeesTheFirstConnectionOnceAutoIgnoreIsOn() async throws {
            let seen = try await firstRejectedHandshake(autoIgnore: true)
            #expect(seen.abandoned.first == "pinned.test")
            #expect(seen.suspected == ["pinned.test"])
        }
    }
}
