import NIO
@testable import WatcherCore
import WatcherTestSupport
import XCTest

final class ProtocolDepthTests: XCTestCase {
    func testPermessageDeflateKeepsTheWindowBetweenMessages() throws {
        // Produced by Python: zlib.compressobj(wbits=-15) with Z_SYNC_FLUSH after each message, tail 00 00 FF FF removed.
        let first = Data(hex: "ca48cdc9c957c840270100"), second = Data(hex: "421628cf2fca4981b00100")
        let store = FlowStore()
        let flow = store.begin(RequestRecord(method: "GET", scheme: "http", host: "a", port: 80, path: "/"))
        let recorder = WebSocketRecorder(store: store, flowID: flow.id)

        func frame(_ payload: Data) -> ByteBuffer { // server -> client: FIN + RSV1 + text, unmasked
            ByteBufferAllocator().buffer(bytes: [0xC1, UInt8(payload.count)] + Array(payload))
        }
        recorder.record(ByteBufferAllocator().buffer(string: "HTTP/1.1 101 Switching Protocols\r\n\r\n"), direction: .serverToClient)
        recorder.record(frame(first), direction: .serverToClient)
        recorder.record(frame(second), direction: .serverToClient)

        let messages = try XCTUnwrap(store.all.first).webSocketMessages
        XCTAssertEqual(messages.map { String(decoding: $0.payload, as: UTF8.self) }, ["hello hello hello hello", "hello hello world hello"])
        XCTAssertEqual(messages.map(\.isCompressed), [false, false])
    }

    func testProtobufSchemaNamesFieldsEnumsAndNestedMessages() throws {
        func varint(_ value: Int) -> [UInt8] {
            var v = value, out: [UInt8] = []; repeat {
                out.append(UInt8(v & 0x7F) | (v > 0x7F ? 0x80 : 0)); v >>= 7
            } while v > 0; return out
        }
        func field(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
            varint(number << 3 | 2) + varint(bytes.count) + bytes
        }
        func number(_ number: Int, _ value: Int) -> [UInt8] {
            varint(number << 3) + varint(value)
        }
        func fieldDescriptor(_ name: String, _ index: Int, label: Int = 1, type: Int, typeName: String = "") -> [UInt8] {
            field(1, Array(name.utf8)) + number(3, index) + number(4, label) + number(5, type) + (typeName.isEmpty ? [] : field(6, Array(typeName.utf8)))
        }
        let address = field(1, Array("Address".utf8)) + field(2, fieldDescriptor("city", 1, type: 9))
        let role = field(1, Array("Role".utf8)) + field(2, field(1, Array("ADMIN".utf8)) + number(2, 1))
        let user = field(1, Array("User".utf8))
            + field(2, fieldDescriptor("name", 1, type: 9)) + field(2, fieldDescriptor("id", 2, type: 5))
            + field(2, fieldDescriptor("tags", 3, label: 3, type: 9)) + field(2, fieldDescriptor("home", 4, type: 11, typeName: ".demo.Address"))
            + field(2, fieldDescriptor("role", 5, type: 14, typeName: ".demo.Role")) + field(2, fieldDescriptor("scores", 6, label: 3, type: 5))
        let file = field(2, Array("demo".utf8)) + field(4, user) + field(4, address) + field(5, role)
        let schema = try ProtobufSchema(descriptorSet: Data(field(1, file)))

        let message = field(1, Array("Ada".utf8)) + number(2, 7) + field(3, Array("a".utf8)) + field(3, Array("b".utf8))
            + field(4, field(1, Array("Paris".utf8))) + number(5, 1) + field(6, varint(3) + varint(300))
        XCTAssertEqual(schema.describe(Data(message), as: "demo.User"), """
        name: "Ada"
        id: 7
        tags: "a"
        tags: "b"
        home {
          city: "Paris"
        }
        role: ADMIN
        scores: 3
        scores: 300
        """)
        XCTAssertNil(schema.describe(Data(message), as: "demo.Missing"))
        XCTAssertThrowsError(try ProtobufSchema(descriptorSet: Data([0xFF])))
    }

    func testWorkspaceRoundTripAndNameValidation() throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-ws-\(UUID().uuidString)"))
        var settings = WatcherSettings(); settings.noCaching = true
        let flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/"))
        try store.save(name: "Checkout bug", flows: [flow], settings: settings)
        XCTAssertEqual(store.list(), ["Checkout bug"])
        let loaded = try store.load(name: "Checkout bug")
        XCTAssertEqual(loaded.flows.count, 1); XCTAssertTrue(loaded.settings.noCaching)
        for bad in ["../escape", "a/b", "", " lead", String(repeating: "x", count: 81)] {
            XCTAssertThrowsError(try store.save(name: bad, flows: [], settings: settings), bad)
        }
        try store.delete(name: "Checkout bug")
        XCTAssertTrue(store.list().isEmpty)
    }

    func testExternalProxyViaPACFileAndViaSocks() async throws {
        let inner = try Harness()
        try await inner.start {
            $0.sslProxying = SSLProxyingSettings(include: [], exclude: [])
            $0.socks = SocksSettings(isEnabled: true, port: 18890)
        }
        defer { Task { await inner.stop() } }

        func outerEngine(_ external: ExternalProxySettings) throws -> WatcherEngine {
            let engine = try WatcherEngine(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)"))
            try engine.settings.update { $0.externalProxy = external }
            return engine
        }
        let request = RequestRecord(method: "GET", scheme: "http", host: "upstream.test", port: inner.upstream.port, path: "/chained")

        // PAC loaded from a file:// URL points at the inner HTTP proxy.
        let pacFile = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).pac")
        try Data("function FindProxyForURL(url, host) { return shExpMatch(host, '*.test') ? 'PROXY 127.0.0.1:\(inner.proxyPort)' : 'DIRECT'; }".utf8).write(to: pacFile)
        let viaPAC = try outerEngine(ExternalProxySettings(isEnabled: true, kind: .pac, pacURL: pacFile.absoluteString))
        try await viaPAC.start(port: 0)
        let pacResponse = await viaPAC.send(request)
        try await viaPAC.stop()
        XCTAssertEqual(pacResponse.status, 200)
        XCTAssertTrue(String(decoding: pacResponse.body, as: UTF8.self).hasPrefix("GET /chained"))

        // SOCKS: the inner engine's own SOCKS5 listener. upstream.test only resolves inside it (blind tunnel + DNS Spoofing).
        let viaSocks = try outerEngine(ExternalProxySettings(isEnabled: true, kind: .socks, host: "127.0.0.1", port: 18890))
        try await viaSocks.start(port: 0)
        let socksResponse = await viaSocks.send(request)
        try await viaSocks.stop()
        XCTAssertEqual(socksResponse.status, 200)
        XCTAssertTrue(String(decoding: socksResponse.body, as: UTF8.self).hasPrefix("GET /chained"))
    }
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map { UInt8(hex.dropFirst($0).prefix(2), radix: 16)! })
    }
}

/// Port suggestions and other small behaviours of the engine.
final class EngineDetailTests: XCTestCase {
    func testPortFinderStartsAt10000SkipsTakenAndBusyPorts() throws {
        XCTAssertEqual(PortFinder.firstAvailable(avoiding: []).map { $0 >= 10000 }, true)
        let first = try XCTUnwrap(PortFinder.firstAvailable())
        XCTAssertEqual(try XCTUnwrap(PortFinder.firstAvailable(avoiding: [first])) > first, true)

        // A port that is really listening must be skipped even if no rule uses it.
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(first).bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(bound, 0)
        XCTAssertNotEqual(PortFinder.firstAvailable(), first)
    }

    func testEngineSuggestionAvoidsPortsUsedByRules() throws {
        let engine = try WatcherEngine(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)"))
        let first = try XCTUnwrap(engine.suggestReversePort())
        try engine.settings.update { $0.reverseProxy.rules = [ReverseProxyRule(localPort: first, remoteHost: "a.com")] }
        XCTAssertNotEqual(engine.suggestReversePort(), first)
    }

    func testCustomThrottleProfilesSaveReplaceDeleteAndKeepPresetsSafe() throws {
        var throttle = ThrottleSettings()
        throttle.profile = NetworkProfile(name: "Office VPN", downloadKbps: 2000, latencyMilliseconds: 80)
        throttle.saveCurrentProfile()
        throttle.profile.latencyMilliseconds = 120
        throttle.saveCurrentProfile()
        XCTAssertEqual(throttle.customProfiles.map(\.latencyMilliseconds), [120])
        XCTAssertTrue(throttle.availableProfiles.contains { $0.name == "Office VPN" } && throttle.availableProfiles.contains { $0.name == "3G" })

        throttle.profile = NetworkProfile(name: "3G", latencyMilliseconds: 1)
        throttle.saveCurrentProfile()
        XCTAssertEqual(throttle.customProfiles.count, 1, "presets must not be overwritten")

        throttle.deleteCustomProfile(named: "Office VPN")
        XCTAssertTrue(throttle.customProfiles.isEmpty)
        // Settings written before custom profiles existed still load.
        let old = try JSONDecoder().decode(ThrottleSettings.self, from: Data(#"{"isEnabled":true,"host":"a"}"#.utf8))
        XCTAssertTrue(old.isEnabled); XCTAssertTrue(old.customProfiles.isEmpty)
    }

    func testAbortAllAnswersEveryHeldRequestWith502() async throws {
        let harness = try Harness()
        try await harness.start {
            $0.breakpoints = RuleSet(isEnabled: true, rules: [BreakpointRule(matching: MatchingRule(pattern: "*/bp*"), onResponse: false)])
        }
        defer { Task { await harness.stop() } }

        async let first = harness.get("/bp?1"), second = harness.get("/bp?2")
        for _ in 0 ..< 60 where harness.engine.breakpoints.pending.count < 2 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(harness.engine.breakpoints.pending.count, 2)
        harness.engine.breakpoints.abortAll()
        let results = try await [first.status, second.status]
        XCTAssertEqual(results, [502, 502])
        XCTAssertTrue(harness.engine.breakpoints.pending.isEmpty)
    }
}
