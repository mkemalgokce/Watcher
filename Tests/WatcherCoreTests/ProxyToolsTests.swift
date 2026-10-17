@testable import WatcherCore
import WatcherTestSupport
import XCTest

final class ProxyToolsTests: XCTestCase {
    private var harness: Harness!

    override func setUp() async throws {
        harness = try Harness()
    }

    override func tearDown() async throws {
        await harness.stop()
    }

    func testForwardsAndRecordsFlow() async throws {
        try await harness.start()
        let (status, body) = try await harness.get("/hello")
        XCTAssertEqual(status, 200)
        XCTAssertTrue(body.hasPrefix("GET /hello"), body)
        XCTAssertEqual(harness.engine.store.all.first?.response?.status, 200)
    }

    func testRecordsBodilessResponses() async throws {
        try await harness.start()
        for (method, path, status) in [("GET", "/empty", 200), ("GET", "/nocontent", 204), ("GET", "/close", 200), ("HEAD", "/head", 200), ("GET", "/notmodified", 304)] {
            let result = try await harness.get(path, method: method)
            XCTAssertEqual(result.status, status, path); XCTAssertEqual(result.body, "", path)
            for _ in 0 ..< 20 where harness.engine.store.all.first(where: { $0.request.path == path })?.state != .completed {
                try await Task.sleep(for: .milliseconds(50))
            }
            let flow = try XCTUnwrap(harness.engine.store.all.first { $0.request.path == path }, path)
            XCTAssertEqual(flow.response?.status, status, path)
            XCTAssertEqual(flow.state, .completed, path)
        }
    }

    func testResponseBreakpointOnEmptyBody() async throws {
        try await harness.start {
            $0.breakpoints = RuleSet(isEnabled: true, rules: [BreakpointRule(matching: MatchingRule(pattern: "*/empty"), onRequest: false, onResponse: true)])
        }
        async let pending = harness.get("/empty")
        for _ in 0 ..< 50 where harness.engine.breakpoints.pending.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        let hit = try XCTUnwrap(harness.engine.breakpoints.pending.first)
        XCTAssertEqual(hit.response?.status, 200)
        harness.engine.breakpoints.resolve(hit.id, with: .proceed(request: hit.request, response: hit.response))
        let result = try await pending
        XCTAssertEqual(result.status, 200); XCTAssertEqual(result.body, "")
    }

    func testBlockListShowsOrHidesRequest() async throws {
        try await harness.start {
            $0.blockList = RuleSet(isEnabled: true, rules: [
                BlockRule(matching: MatchingRule(pattern: "*/shown"), hidesRequest: false),
                BlockRule(matching: MatchingRule(pattern: "*/hidden"), hidesRequest: true),
            ])
        }
        let shown = try await harness.get("/shown")
        let hidden = try await harness.get("/hidden")
        XCTAssertEqual(shown.status, 403); XCTAssertEqual(hidden.status, 403)
        XCTAssertEqual(harness.engine.store.all.map(\.request.path), ["/shown"])
    }

    func testAllowListBlocksEverythingElse() async throws {
        try await harness.start { $0.allowList = RuleSet(isEnabled: true, rules: [AllowRule(matching: MatchingRule(pattern: "*/ok"))]) }
        let allowed = try await harness.get("/ok")
        let denied = try await harness.get("/nope")
        XCTAssertEqual(allowed.status, 200); XCTAssertEqual(denied.status, 403)
    }

    func testMapLocalServesFileAndHonoursHTTPMessageFormat() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).json")
        try Data("HTTP/1.1 201 Created\r\nX-Mocked: yes\r\n\r\n{\"mock\":true}".utf8).write(to: file)
        try await harness.start {
            $0.mapLocal = RuleSet(isEnabled: true, rules: [MapLocalRule(matching: MatchingRule(pattern: "*/mock"), source: .file(file.path))])
        }
        let result = try await harness.get("/mock")
        XCTAssertEqual(result.status, 201)
        XCTAssertEqual(result.body, "{\"mock\":true}")
    }

    func testMapRemoteRewritesPathAndHost() async throws {
        try await harness.start {
            $0.mapRemote = RuleSet(isEnabled: true, rules: [MapRemoteRule(
                matching: MatchingRule(pattern: "*/old"), destination: .init(path: "/new", query: "a=1")
            )])
        }
        let result = try await harness.get("/old")
        XCTAssertTrue(result.body.hasPrefix("GET /new?a=1"), result.body)
    }

    func testScriptEditsRequestAndResponse() async throws {
        let source = """
        async function onRequest(context, url, request) { request.headers["X-Script"] = "yes"; return request; }
        async function onResponse(context, url, request, response) { response.statusCode = 418; response.body = response.body + " [scripted]"; return response; }
        """
        try await harness.start {
            $0.scripting = RuleSet(isEnabled: true, rules: [ScriptRule(matching: MatchingRule(pattern: "*/script"), source: source)])
        }
        let result = try await harness.get("/script")
        XCTAssertEqual(result.status, 418)
        XCTAssertTrue(result.body.contains("script=yes") && result.body.hasSuffix("[scripted]"), result.body)
    }

    func testBreakpointHoldsUntilResolvedAndAppliesEdit() async throws {
        try await harness.start {
            $0.breakpoints = RuleSet(isEnabled: true, rules: [BreakpointRule(matching: MatchingRule(pattern: "*/bp"), onResponse: false)])
        }
        async let pending = harness.get("/bp")
        for _ in 0 ..< 50 where harness.engine.breakpoints.pending.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        var hit = try XCTUnwrap(harness.engine.breakpoints.pending.first)
        hit.request.path = "/edited"
        harness.engine.breakpoints.resolve(hit.id, with: .proceed(request: hit.request, response: nil))
        let result = try await pending
        XCTAssertTrue(result.body.hasPrefix("GET /edited"), result.body)
    }

    func testBreakpointAbort() async throws {
        try await harness.start {
            $0.breakpoints = RuleSet(isEnabled: true, rules: [BreakpointRule(matching: MatchingRule(pattern: "*/bp"), onResponse: false)])
        }
        async let pending = harness.get("/bp")
        for _ in 0 ..< 50 where harness.engine.breakpoints.pending.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        try harness.engine.breakpoints.resolve(XCTUnwrap(harness.engine.breakpoints.pending.first).id, with: .abort)
        let aborted = try await pending
        XCTAssertEqual(aborted.status, 502)
    }

    func testThrottleDropsPacketsAndAddsLatency() async throws {
        try await harness.start {
            $0.throttle = ThrottleSettings(isEnabled: true, profile: NetworkProfile(name: "lossy", packetLossPercent: 100))
        }
        let dropped = try await harness.get("/x")
        XCTAssertEqual(dropped.status, 504)

        try await harness.reconfigure { $0.throttle = ThrottleSettings(isEnabled: true, profile: NetworkProfile(name: "slow", latencyMilliseconds: 300)) }
        let start = Date()
        _ = try await harness.get("/x")
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.55) // 300 ms each way
    }

    func testNoCachingAddsHeaders() async throws {
        try await harness.start { $0.noCaching = true }
        _ = try await harness.get("/cache", headers: [("If-None-Match", "abc")])
        let sent = try XCTUnwrap(harness.engine.store.all.first).request
        XCTAssertNil(sent.headers.value(for: "if-none-match"))
        XCTAssertEqual(sent.headers.value(for: "cache-control"), "no-cache, no-store")
    }

    func testReverseProxyForwardsLocalPortToOrigin() async throws {
        try await harness.start()
        let port = try await harness.upstream.port
        try await harness.reconfigure {
            $0.reverseProxy = RuleSet(isEnabled: true, rules: [ReverseProxyRule(localPort: 19431, remoteHost: "upstream.test", remotePort: port)])
        }
        let direct = HTTPClientRequestHelper.url("http://127.0.0.1:19431/rp")
        let body = try await HTTPClientRequestHelper.fetch(direct)
        XCTAssertTrue(body.hasPrefix("GET /rp host=upstream.test"), body)
    }
}
