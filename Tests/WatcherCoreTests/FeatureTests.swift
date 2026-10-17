@testable import WatcherCore
import XCTest

final class WebSocketTests: XCTestCase {
    func testUpgradeIsRecordedAndBytesAreRelayedBothWays() async throws {
        let harness = try Harness()
        let origin = UpgradeOrigin()
        try await origin.start()
        try await harness.start()
        defer { Task { await harness.stop(); await origin.stop() } }

        let client = RawClient()
        try await client.connect(port: harness.proxyPort)
        try await client.send("GET http://127.0.0.1:\(origin.port)/ws HTTP/1.1\r\nHost: 127.0.0.1:\(origin.port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        let handshake = await client.received(containing: "101 Switching Protocols")
        XCTAssertTrue(handshake.contains("101 Switching Protocols"), handshake)

        try await client.send("hello-frames")
        let echoed = await client.received(containing: "hello-frames")
        XCTAssertTrue(echoed.hasSuffix("hello-frames"), echoed)
        await client.close()

        let flow = try XCTUnwrap(harness.engine.store.all.first)
        XCTAssertEqual(flow.response?.status, 101)
        XCTAssertEqual(flow.request.path, "/ws")
    }
}

final class FeatureTests: XCTestCase {
    func testRuleExportAndImportModes() {
        var local = WatcherSettings()
        local.port = 1111
        local.blockList = RuleSet(isEnabled: true, rules: [BlockRule(name: "keep", matching: MatchingRule(pattern: "a"))])
        var incoming = WatcherSettings()
        incoming.port = 2222
        incoming.blockList = RuleSet(isEnabled: true, rules: [
            BlockRule(name: "on", matching: MatchingRule(pattern: "b")),
            BlockRule(name: "off", isEnabled: false, matching: MatchingRule(pattern: "c")),
        ])

        XCTAssertEqual(incoming.exported(.enabledRules).blockList.rules.map(\.name), ["on"])
        XCTAssertEqual(incoming.exported(.all).blockList.rules.count, 2)

        let appended = local.importing(incoming, mode: .append)
        XCTAssertEqual(appended.blockList.rules.map(\.name), ["keep", "on", "off"])
        XCTAssertEqual(appended.port, 1111)
        let replaced = local.importing(incoming, mode: .override)
        XCTAssertEqual(replaced.blockList.rules.count, 2)
        XCTAssertEqual(replaced.port, 2222)
    }

    func testCharlesJSONImport() throws {
        let json = """
        [{"scheme":"https","host":"api.example.com","port":443,"method":"POST","path":"/v1/login","query":"a=1",
          "request":{"header":{"headers":[{"name":"Content-Type","value":"application/json"}]},"body":{"text":"{\\"u\\":1}"}},
          "response":{"status":200,"header":{"headers":[]},"body":{"encoded":"aGk="}},
          "times":{"start":"2026-10-16T10:00:00.000Z"},"durations":{"total":120}}]
        """
        let flow = try XCTUnwrap(CharlesSession.flows(from: Data(json.utf8)).first)
        XCTAssertEqual(flow.request.url, "https://api.example.com/v1/login?a=1")
        XCTAssertEqual(flow.request.body, Data(#"{"u":1}"#.utf8))
        XCTAssertEqual(flow.response?.body, Data("hi".utf8))
        XCTAssertEqual(flow.duration ?? 0, 0.12, accuracy: 0.001)
        XCTAssertThrowsError(try CharlesSession.flows(from: Data("not json".utf8)))
    }

    func testTextDiff() {
        let lines = TextDiff.lines(from: "a\nb\nc", to: "a\nx\nc")
        XCTAssertEqual(lines.map(\.kind), [.same, .removed, .added, .same])
        XCTAssertEqual(lines.filter { $0.kind == .added }.map(\.text), ["x"])
    }

    func testProtobufWireDecodeAndRejectGarbage() {
        // field 1 = 150 (varint), field 2 = "hi", field 3 = nested { 1: 7 }
        let message = Data([0x08, 0x96, 0x01, 0x12, 0x02, 0x68, 0x69, 0x1A, 0x02, 0x08, 0x07])
        let text = ProtobufWire.describe(message)
        XCTAssertEqual(text, "1: 150\n2: \"hi\"\n3 {\n  1: 7\n}")
        XCTAssertNil(ProtobufWire.describe(Data([0xFF, 0xFF, 0xFF])))
    }

    func testBodyPreviewGraphQLAndGRPC() {
        let body = Data(#"{"operationName":"GetUser","query":"query GetUser { me { id } }","variables":{"id":1}}"#.utf8)
        let graphQL = BodyPreview.text(body, contentType: "application/json")
        XCTAssertTrue(graphQL.hasPrefix("# operation: GetUser") && graphQL.contains("# variables"), graphQL)
        let grpc = Data([0, 0, 0, 0, 2, 0x08, 0x07])
        XCTAssertEqual(BodyPreview.text(grpc, contentType: "application/grpc"), "1: 7")
    }
}

final class StreamingTests: XCTestCase {
    func testEventStreamIsRelayedIncrementallyAndCapturedWhole() async throws {
        let harness = try Harness()
        let origin = StreamOrigin()
        try await origin.start()
        try await harness.start()
        defer { Task { await harness.stop(); await origin.stop() } }

        let client = RawClient()
        try await client.connect(port: harness.proxyPort)
        let started = Date()
        try await client.send("GET http://127.0.0.1:\(origin.port)/events HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")

        let first = await client.received(containing: "data: one")
        let firstArrival = Date().timeIntervalSince(started)
        XCTAssertTrue(first.contains("data: one") && !first.contains("data: two"), first)
        XCTAssertLessThan(firstArrival, 0.9, "first event must not wait for the stream to finish")

        let all = await client.received(containing: "data: two")
        XCTAssertTrue(all.contains("data: two"), all)
        await client.close()

        for _ in 0 ..< 40 where harness.engine.store.all.first?.state != .completed {
            try await Task.sleep(for: .milliseconds(50))
        }
        let flow = try XCTUnwrap(harness.engine.store.all.first)
        XCTAssertEqual(flow.state, .completed)
        XCTAssertEqual(String(decoding: flow.response?.body ?? Data(), as: UTF8.self), "data: one\n\ndata: two\n\n")
    }
}
