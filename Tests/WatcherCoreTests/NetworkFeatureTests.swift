@testable import WatcherCore
import WatcherTestSupport
import XCTest

final class NetworkFeatureTests: XCTestCase {
    func testSocks5PlainHTTPIsRecorded() async throws {
        let harness = try Harness()
        try await harness.start { $0.socks = SocksSettings(isEnabled: true, port: 18889) }
        defer { Task { await harness.stop() } }

        let client = RawClient()
        try await client.connect(port: 18889)
        try await client.send(bytes: [5, 1, 0])
        let port = harness.upstream.port
        try await client.send(bytes: [5, 1, 0, 1, 127, 0, 0, 1, UInt8(port >> 8), UInt8(port & 0xFF)])
        let handshake = await client.receivedBytes(atLeast: 12)
        XCTAssertEqual(handshake, [5, 0, 5, 0, 0, 1, 0, 0, 0, 0, 0, 0])

        try await client.send("GET /socks HTTP/1.1\r\nHost: x\r\n\r\n")
        let reply = await client.received(containing: "GET /socks")
        XCTAssertTrue(reply.contains("200 OK") && reply.contains("GET /socks"), reply)
        await client.close()
        XCTAssertEqual(harness.engine.store.all.first?.request.url, "http://127.0.0.1:\(port)/socks")
    }

    func testPACEvaluatorRoutes() throws {
        let pac = try PACEvaluator(script: """
        function FindProxyForURL(url, host) {
          if (shExpMatch(host, "*.internal.test")) return "PROXY proxy.local:3128; DIRECT";
          if (dnsDomainIs(host, ".corp")) return "SOCKS socks.local:1080";
          return "DIRECT";
        }
        """)
        XCTAssertEqual(pac.route(for: "http://a.internal.test/", host: "a.internal.test"), .http(host: "proxy.local", port: 3128))
        XCTAssertEqual(pac.route(for: "http://wiki.corp/", host: "wiki.corp"), .socks(host: "socks.local", port: 1080))
        XCTAssertEqual(pac.route(for: "http://example.com/", host: "example.com"), .direct)
        XCTAssertThrowsError(try PACEvaluator(script: "var nothing = 1;"))
    }

    func testExternalProxyChainReachesOriginOnlyKnownToTheProxy() async throws {
        // B resolves upstream.test (DNS Spoofing) and tunnels blindly; A knows nothing but B.
        let inner = try Harness()
        try await inner.start { $0.sslProxying = SSLProxyingSettings(include: [], exclude: []) }
        defer { Task { await inner.stop() } }

        let outer = try WatcherEngine(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)"))
        try outer.settings.update { $0.externalProxy = ExternalProxySettings(isEnabled: true, kind: .http, host: "127.0.0.1", port: inner.proxyPort) }
        try await outer.start(port: 0)
        defer { Task { try? await outer.stop() } }

        let response = await outer.send(RequestRecord(method: "GET", scheme: "http", host: "upstream.test", port: inner.upstream.port, path: "/via-proxy"))
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(String(decoding: response.body, as: UTF8.self).hasPrefix("GET /via-proxy"))
    }

    func testWebSocketMessagesAreDecodedBothWays() async throws {
        let harness = try Harness()
        let origin = UpgradeOrigin()
        try await origin.start()
        try await harness.start()
        defer { Task { await harness.stop(); await origin.stop() } }

        let client = RawClient()
        try await client.connect(port: harness.proxyPort)
        try await client.send("GET http://127.0.0.1:\(origin.port)/ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        _ = await client.received(containing: "101 Switching Protocols")
        // Masked text frame "hi" (key 01 02 03 04); the origin echoes the same bytes back.
        try await client.send(bytes: [0x81, 0x82, 1, 2, 3, 4, UInt8(ascii: "h") ^ 1, UInt8(ascii: "i") ^ 2])

        var messages: [WebSocketMessage] = []
        for _ in 0 ..< 60 {
            messages = harness.engine.store.all.first?.webSocketMessages ?? []
            if messages.count >= 2 {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        await client.close()
        XCTAssertEqual(messages.map(\.direction), [.clientToServer, .serverToClient])
        XCTAssertEqual(messages.map { String(decoding: $0.payload, as: UTF8.self) }, ["hi", "hi"])
        XCTAssertEqual(messages.first?.kind, .text)
    }

    func testLargeUploadIsStreamedNotBuffered() async throws {
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }

        let size = 9 * 1024 * 1024
        let reply = try await harness.post("/upload", body: Data(repeating: 0x41, count: size))
        XCTAssertTrue(reply.contains("bytes=\(size)"), reply)
        // A streamed upload is recorded without its body; a buffered one would keep all 9 MB.
        XCTAssertEqual(harness.engine.store.all.first?.request.body.count, 0)
    }

    func testComposeFollowsRedirectsAndRecordsEachHop() async throws {
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }

        let request = RequestRecord(method: "GET", scheme: "http", host: "upstream.test", port: harness.upstream.port, path: "/redirect")
        let plain = await harness.engine.send(request)
        XCTAssertEqual(plain.status, 302)
        let followed = await harness.engine.send(request, followRedirects: true)
        XCTAssertTrue(String(decoding: followed.body, as: UTF8.self).hasPrefix("GET /final"))
        XCTAssertEqual(harness.engine.store.all.map(\.request.path), ["/redirect", "/redirect", "/final"])
    }
}

final class ConfigurationTests: XCTestCase {
    func testSettingsFromOlderVersionStillLoadWithDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).json")
        try Data(#"{"port": 1234, "noCaching": true, "externalProxy": {"isEnabled": true, "host": "h", "port": 1}}"#.utf8).write(to: url)
        let settings = SettingsStore(url: url).value
        XCTAssertEqual(settings.port, 1234)
        XCTAssertTrue(settings.noCaching)
        XCTAssertEqual(settings.externalProxy.host, "h")
        XCTAssertEqual(settings.socks, SocksSettings())
        XCTAssertFalse(settings.listenOnAllInterfaces)
    }

    func testSessionsFromOlderVersionStillOpen() throws {
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/"))
        flow.webSocketMessages = [WebSocketMessage(direction: .clientToServer, kind: .text, payload: Data("x".utf8))]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(flow)) as? [String: Any])
        object.removeValue(forKey: "webSocketMessages")
        let decoded = try JSONDecoder().decode(Flow.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.webSocketMessages.isEmpty)
    }

    func testSystemProxyIssuesCommandsForEnabledServicesOnly() throws {
        final class Calls: @unchecked Sendable { let lock = NSLock(); var list: [[String]] = []; func add(_ c: [String]) {
            lock.withLock { list.append(c) }
        } }
        let calls = Calls()
        // Never the real ~/.watcher backup: tests must not read or delete the user's saved proxy settings.
        let proxy = SystemProxy(run: { arguments in
            calls.add(arguments)
            return arguments.first == "-listallnetworkservices"
                ? "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n*USB LAN\nThunderbolt Bridge\n" : ""
        }, backupURL: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-sp-\(UUID().uuidString).json"))
        try proxy.enable(port: 9090)
        XCTAssertTrue(calls.list.contains(["-setwebproxy", "Wi-Fi", "127.0.0.1", "9090"]))
        XCTAssertTrue(calls.list.contains(["-setsecurewebproxy", "Thunderbolt Bridge", "127.0.0.1", "9090"]))
        XCTAssertFalse(calls.list.contains { $0.contains("USB LAN") })
        try proxy.disable()
        XCTAssertTrue(calls.list.contains(["-setwebproxystate", "Wi-Fi", "off"]))
    }

    func testCharlesConverterReportsMissingInstall() async {
        do {
            _ = try await CharlesConverter.flows(from: URL(fileURLWithPath: "/tmp/x.chls"), charles: URL(fileURLWithPath: "/nonexistent/Charles"))
            XCTFail("expected an error")
        } catch let error as CharlesConverter.ConversionError {
            XCTAssertTrue("\(error)".contains("not found"))
        } catch { XCTFail("\(error)") }
    }
}

final class MCPServerTests: XCTestCase {
    private func makeServer() throws -> (MCPServer, WatcherEngine) {
        let engine = try WatcherEngine(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)"))
        return (MCPServer(engine: engine), engine)
    }

    private func json(_ line: String?) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(XCTUnwrap(line).utf8)) as? [String: Any])
    }

    func testProtocolBasics() async throws {
        let (server, _) = try makeServer()
        let initialized = try await json(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
        XCTAssertEqual((initialized["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-03-26")
        let notification = await server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(notification)
        let listed = try await json(server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let names = ((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertTrue(["get_flows", "get_flow_detail", "get_websocket_messages", "create_blacklist", "clear_session"].allSatisfy(names.contains))
        let unknown = try await json(server.handle(#"{"jsonrpc":"2.0","id":3,"method":"nope"}"#))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        let garbage = try await json(server.handle("{not json"))
        XCTAssertEqual((garbage["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testToolsChangeSettingsAndValidateArguments() async throws {
        let (server, engine) = try makeServer()
        let created = try await json(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_blacklist","arguments":{"pattern":"*ads*"}}}"#))
        XCTAssertEqual((created["result"] as? [String: Any])?["isError"] as? Bool, false)
        XCTAssertEqual(engine.settings.value.blockList.rules.map(\.matching.pattern), ["*ads*"])
        XCTAssertTrue(engine.settings.value.blockList.isEnabled)

        let missing = try await json(server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_blacklist","arguments":{}}}"#))
        XCTAssertEqual((missing["result"] as? [String: Any])?["isError"] as? Bool, true)

        var flowRequest = RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/x")
        flowRequest.headers = [Header("Accept", "*/*")]
        engine.store.load([Flow(sequence: 1, request: flowRequest)])
        let curl = try await json(server.handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"export_flow_curl","arguments":{"sequence":"1"}}}"#))
        let text = (((curl["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertEqual(text, "curl 'https://a.com/x' -H 'Accept: */*'")
    }
}
