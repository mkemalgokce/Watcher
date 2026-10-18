import AsyncHTTPClient
import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    /// The callbacks a caller installs before `start` are what the very first connection reports to: the server reads
    /// them under its lock, so nothing the caller set up first can be missed. Awaiting a stream rather than polling
    /// keeps the test free of sleeps and of any guess about timing.
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
            let (abandoned, abandonedSink) = AsyncStream<String>.makeStream()
            let (suspected, suspectedSink) = AsyncStream<String>.makeStream()
            server.onHandshakeAbandoned = { abandonedSink.yield($0) }
            server.onPinningSuspected = { suspectedSink.yield($0) }
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
            var firstAbandoned = abandoned.makeAsyncIterator()
            let first = await firstAbandoned.next()
            request.cancel()
            try? await client.shutdown()
            try await server.stop()
            abandonedSink.finish(); suspectedSink.finish()

            var seenAbandoned = first.map { [$0] } ?? []
            while let host = await firstAbandoned.next() {
                seenAbandoned.append(host)
            }
            var seenSuspected: [String] = []
            for await host in suspected {
                seenSuspected.append(host)
            }
            return (seenAbandoned, seenSuspected)
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
