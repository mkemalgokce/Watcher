import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    /// What a failed TLS handshake with Watcher's certificate reports, and when it is a pinning suspect.
    @Suite(.tags(.unit))
    struct Pinning {
        private func server(autoIgnore: Bool) -> (
            ProxyServer,
            pinned: LockedBox<[String]>,
            abandoned: LockedBox<[String]>
        ) {
            let server = ProxyServer(authority: nil)
            var settings = WatcherSettings()
            settings.autoIgnoreSSLPinning = autoIgnore
            server.updatePolicies(settings)
            let pinned = LockedBox<[String]>([])
            let abandoned = LockedBox<[String]>([])
            server.onPinningSuspected = { host in pinned.mutate { $0.append(host) } }
            server.onHandshakeAbandoned = { host in abandoned.mutate { $0.append(host) } }
            return (server, pinned, abandoned)
        }

        @Test
        func withAutoIgnoreOffTheAbandonmentIsObservedButNotReportedAsPinning() {
            let (server, pinned, abandoned) = server(autoIgnore: false)
            server.handshakeFailed(host: "a.test")
            #expect(abandoned.value == ["a.test"])
            #expect(pinned.value.isEmpty)
        }

        @Test
        func withAutoIgnoreOnAHostIsReportedOnceEvenAfterTwoFailures() {
            let (server, pinned, abandoned) = server(autoIgnore: true)
            server.handshakeFailed(host: "a.test")
            server.handshakeFailed(host: "a.test")
            #expect(pinned.value == ["a.test"])
            #expect(abandoned.value == ["a.test", "a.test"])
        }

        @Test
        func eachHostIsReportedOnce() {
            let (server, pinned, _) = server(autoIgnore: true)
            server.handshakeFailed(host: "a.test")
            server.handshakeFailed(host: "b.test")
            #expect(pinned.value == ["a.test", "b.test"])
        }

        @Test
        func aFailureWithNoObserverIsHarmless() {
            let server = ProxyServer(authority: nil)
            server.handshakeFailed(host: "a.test")
        }
    }
}
