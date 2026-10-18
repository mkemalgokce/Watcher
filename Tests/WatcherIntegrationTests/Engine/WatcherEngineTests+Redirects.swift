import AsyncHTTPClient
import Foundation
import NIOHTTP1
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension WatcherEngineTests {
    /// Compose following redirects against a scripted upstream: which hop keeps which headers and body.
    @Suite(.timeLimit(.minutes(1)), .tags(.integration))
    struct Redirects {
        private static let credentials = [
            Header("Authorization", "Bearer secret"), Header("Cookie", "sid=1"),
            Header("Proxy-Authorization", "Basic x"),
            Header("Content-Type", "text/plain"), Header("Content-Length", "4"), Header("X-Keep", "yes"),
        ]

        private static func redirect(_ status: UInt, to location: String?) -> HTTPClientResponse {
            var headers: HTTPHeaders = ["Content-Length": "0"]
            if let location {
                headers.add(name: "Location", value: location)
            }
            return HTTPClientResponse(status: .init(statusCode: Int(status)), headers: headers)
        }

        private func engine(_ upstream: UpstreamStub) throws -> WatcherEngine {
            try WatcherEngine(directory: URL(fileURLWithPath: "/fake-home/.watcher"), files: FileAccessFake().access) {
                ProxyServer(store: $0, authority: $1, upstream: upstream)
            }
        }

        /// The first request is answered with a redirect; whatever follows with 200.
        private func followed(
            _ status: UInt,
            to location: String?,
            method: String = "POST",
            host: String = "a.test"
        ) async throws -> [RequestRecord] {
            let upstream = UpstreamStub { record in
                record.path == "/start" && record.host == "a.test"
                    ? Self.redirect(status, to: location) : HTTPClientResponse(status: .ok)
            }
            let engine = try engine(upstream)
            _ = try await engine.start(port: 0)
            let request = RequestRecord.fixture(
                method: method, host: host, path: "/start", headers: Self.credentials, body: Data("body".utf8)
            )
            _ = await engine.send(request, followRedirects: true)
            try await engine.stop()
            return upstream.sent.map(\.record)
        }

        private func names(_ record: RequestRecord) -> Set<String> {
            Set(record.headers.map { $0.name.lowercased() })
        }

        @Test(arguments: ["https://other.test/x", "//other.test/x", "http://a.test/x", "https://a.test:8443/x"])
        func credentialsDoNotFollowARedirectToAnotherOrigin(location: String) async throws {
            let hops = try await followed(302, to: location, method: "GET")
            let second = try #require(hops.last)
            #expect(hops.count == 2)
            #expect(names(second).isDisjoint(with: ["authorization", "cookie", "proxy-authorization"]), "\(location)")
            #expect(names(second).contains("x-keep"))
        }

        @Test(arguments: ["/next", "https://a.test/next", "next"])
        func credentialsStayOnTheSameOrigin(location: String) async throws {
            let hops = try await followed(302, to: location, method: "GET")
            let second = try #require(hops.last)
            #expect(names(second).isSuperset(of: ["authorization", "cookie", "proxy-authorization"]), "\(location)")
        }

        @Test(arguments: [
            (UInt(301), "POST", "GET"), (302, "POST", "GET"), (303, "POST", "GET"), (303, "PUT", "GET"),
            (301, "GET", "GET"), (307, "POST", "POST"), (308, "PUT", "PUT"),
        ])
        func theMethodAndBodyFollowTheStatus(status: UInt, method: String, expected: String) async throws {
            let hops = try await followed(status, to: "/next", method: method)
            let second = try #require(hops.last)
            #expect(second.method == expected)
            let keepsBody = expected == method
            #expect(second.body == (keepsBody ? Data("body".utf8) : Data()))
            #expect(names(second).contains("content-type") == keepsBody)
            #expect(names(second).contains("content-length") == keepsBody)
        }

        @Test
        func aRelativeLocationKeepsTheOriginAndAPathOnly() async throws {
            let hops = try await followed(302, to: "next?q=1", method: "GET")
            let second = try #require(hops.last)
            #expect(second.host == "a.test")
            #expect(second.path == "/next?q=1")
        }

        @Test(arguments: [nil, "", "http://"] as [String?])
        func aMissingOrUnusableLocationStops(location: String?) async throws {
            #expect(try await followed(302, to: location).count == 1)
        }

        @Test
        func aRedirectLoopStopsAfterTenHops() async throws {
            let upstream = UpstreamStub { _ in Self.redirect(302, to: "/again") }
            let engine = try engine(upstream)
            _ = try await engine.start(port: 0)
            let last = await engine.send(.fixture(path: "/start"), followRedirects: true)
            try await engine.stop()
            #expect(upstream.sent.count == 11)
            #expect(last.status == 302)
        }

        @Test
        func redirectsAreNotFollowedUnlessAsked() async throws {
            let upstream = UpstreamStub { _ in Self.redirect(302, to: "/again") }
            let engine = try engine(upstream)
            _ = try await engine.start(port: 0)
            let response = await engine.send(.fixture())
            try await engine.stop()
            #expect(upstream.sent.count == 1)
            #expect(response.status == 302)
        }

        @Test
        func aStoppedEngineAnswers503() async throws {
            let response = try await (engine(UpstreamStub())).send(.fixture())
            #expect(response.status == 503)
            #expect(String(bytes: response.body, encoding: .utf8)?.contains("Watcher is not running") == true)
        }

        @Test
        func theTimeoutArgumentOverridesTheSetting() async throws {
            let upstream = UpstreamStub()
            let engine = try engine(upstream)
            try engine.settings.update { $0.composeTimeoutSeconds = 30 }
            _ = try await engine.start(port: 0)
            _ = await engine.send(.fixture(), timeout: 7)
            _ = await engine.send(.fixture())
            try await engine.stop()
            #expect(upstream.sent.map(\.timeout) == [.seconds(7), .seconds(30)])
        }
    }
}
