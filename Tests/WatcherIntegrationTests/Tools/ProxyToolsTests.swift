import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// Each tool applied to real traffic through the proxy.
@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network), .serialized)
struct ProxyToolsTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test
    func blockListShowsOrHidesTheRequest() async throws {
        try await withHarness(configure: {
            $0.blockList = RuleSet(isEnabled: true, rules: [
                BlockRule(matching: MatchingRule(pattern: "*/shown"), hidesRequest: false),
                BlockRule(matching: MatchingRule(pattern: "*/hidden"), hidesRequest: true),
            ])
        }) { harness in
            let shown = try await harness.get("/shown")
            let hidden = try await harness.get("/hidden")
            #expect(shown.status == 403); #expect(hidden.status == 403)
            #expect(harness.engine.store.all.map(\.request.path) == ["/shown"])
        }
    }

    @Test
    func allowListBlocksEverythingElse() async throws {
        try await withHarness(configure: {
            $0.allowList = RuleSet(isEnabled: true, rules: [AllowRule(matching: MatchingRule(pattern: "*/ok"))])
        }) { harness in
            let allowed = try await harness.get("/ok")
            let denied = try await harness.get("/nope")
            #expect(allowed.status == 200); #expect(denied.status == 403)
        }
    }

    @Test
    func mapLocalServesAFileAndHonoursTheHTTPMessageFormat() async throws {
        let file = directory.appending("mock.json")
        try Data("HTTP/1.1 201 Created\r\nX-Mocked: yes\r\n\r\n{\"mock\":true}".utf8).write(to: file)
        try await withHarness(configure: {
            $0.mapLocal = RuleSet(isEnabled: true, rules: [
                MapLocalRule(matching: MatchingRule(pattern: "*/mock"), source: .file(file.path)),
            ])
        }) { harness in
            let result = try await harness.get("/mock")
            #expect(result.status == 201)
            #expect(result.body == "{\"mock\":true}")
        }
    }

    @Test
    func mapRemoteRewritesPathAndQuery() async throws {
        try await withHarness(configure: {
            $0.mapRemote = RuleSet(isEnabled: true, rules: [MapRemoteRule(
                matching: MatchingRule(pattern: "*/old"), destination: .init(path: "/new", query: "a=1")
            )])
        }) { harness in
            let result = try await harness.get("/old")
            #expect(result.body.hasPrefix("GET /new?a=1"), "\(result.body)")
        }
    }

    @Test
    func scriptEditsRequestAndResponse() async throws {
        let source = """
        async function onRequest(context, url, request) { request.headers["X-Script"] = "yes"; return request; }
        async function onResponse(context, url, request, response) {
          response.statusCode = 418; response.body = response.body + " [scripted]"; return response;
        }
        """
        try await withHarness(configure: {
            $0.scripting = RuleSet(isEnabled: true, rules: [
                ScriptRule(matching: MatchingRule(pattern: "*/script"), source: source),
            ])
        }) { harness in
            let result = try await harness.get("/script")
            #expect(result.status == 418)
            #expect(result.body.contains("script=yes") && result.body.hasSuffix("[scripted]"), "\(result.body)")
        }
    }

    @Test(.tags(.timing))
    func throttleDropsPacketsAndAddsLatency() async throws {
        try await withHarness(configure: {
            $0.throttle = ThrottleSettings(
                isEnabled: true,
                profile: NetworkProfile(name: "lossy", packetLossPercent: 100)
            )
        }) { harness in
            let dropped = try await harness.get("/x")
            #expect(dropped.status == 504)

            try await harness.reconfigure {
                $0.throttle = ThrottleSettings(
                    isEnabled: true,
                    profile: NetworkProfile(name: "slow", latencyMilliseconds: 300)
                )
            }
            let start = Date()
            _ = try await harness.get("/x")
            #expect(Date().timeIntervalSince(start) > 0.55) // 300 ms each way
        }
    }

    @Test
    func noCachingStripsValidatorsAndAddsHeaders() async throws {
        try await withHarness(configure: { $0.noCaching = true }) { harness in
            _ = try await harness.get("/cache", headers: [("If-None-Match", "abc")])
            let sent = try #require(harness.engine.store.all.first).request
            #expect(sent.headers.value(for: "if-none-match") == nil)
            #expect(sent.headers.value(for: "cache-control") == "no-cache, no-store")
        }
    }

    @Test
    func markerHeaderNamesTheToolsThatTouchedTheResponse() async throws {
        try await withHarness(configure: { $0.noCaching = true; $0.markModifiedTraffic = true }) { harness in
            let marked = try await harness.getWithHeaders("/m")
            #expect(marked.headers["x-watcher-applied"] == "No Caching")
            try await harness.reconfigure { $0.markModifiedTraffic = false }
            let unmarked = try await harness.getWithHeaders("/m")
            #expect(unmarked.headers["x-watcher-applied"] == nil)
        }
    }

    @Test
    func reverseProxyForwardsALocalPortToTheOrigin() async throws {
        let localPort = try freeLoopbackPort()
        try await withHarness { harness in
            let port = harness.upstream.port
            try await harness.reconfigure {
                $0.reverseProxy = RuleSet(isEnabled: true, rules: [
                    ReverseProxyRule(localPort: localPort, remoteHost: "upstream.test", remotePort: port),
                ])
            }
            let body = try await HTTPClientRequestHelper.fetch(
                HTTPClientRequestHelper.url("http://127.0.0.1:\(localPort)/rp")
            )
            #expect(body.hasPrefix("GET /rp host=upstream.test"), "\(body)")
        }
    }
}
