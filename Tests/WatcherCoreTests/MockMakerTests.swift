@testable import WatcherCore
import WatcherTestSupport
import XCTest

final class MockMakerTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-mocks-\(UUID())")

    private func flow(_ method: String = "GET", path: String = "/v1/users?page=1", status: Int = 200, type: String = "application/json", body: String = #"{"a":1}"#) -> Flow {
        .fixture(
            request: .fixture(method: method, path: path),
            response: .fixture(
                status: status,
                headers: [Header("Content-Type", type), Header("Content-Length", "7")],
                body: Data(body.utf8)
            ),
            state: .pending
        )
    }

    func testPlainJSONFileAndRuleThatMatchesTheSamePathWithAnyQuery() throws {
        let mock = try MockMaker.make(from: flow(), in: folder)
        XCTAssertEqual(mock.file.pathExtension, "json")
        XCTAssertEqual(try Data(contentsOf: mock.file), Data(#"{"a":1}"#.utf8))
        let matcher = mock.rule.matching.compile()
        XCTAssertTrue(matcher.matches(.fixture(method: "GET", path: "/v1/users")))
        XCTAssertTrue(matcher.matches(.fixture(method: "GET", path: "/v1/users?page=2")))
        XCTAssertFalse(matcher.matches(.fixture(method: "POST", path: "/v1/users")))
        XCTAssertFalse(matcher.matches(.fixture(method: "GET", path: "/v1/users/42")))
        XCTAssertFalse(matcher.matches(.fixture(method: "GET", host: "evil-api.example.com", path: "/v1/users")))
    }

    /// A 404 keeps its status: the file is a raw HTTP message that Map Local serves as it is.
    func testNon200KeepsStatusAndHeadersButDropsStaleLengths() throws {
        let mock = try MockMaker.make(from: flow(status: 404, body: #"{"error":"missing"}"#), in: folder)
        XCTAssertEqual(mock.file.pathExtension, "txt")
        let served = try HTTPMessageFile.response(from: Data(contentsOf: mock.file), fileName: mock.file.lastPathComponent)
        XCTAssertEqual(served.status, 404)
        XCTAssertEqual(served.headers.value(for: "Content-Type"), "application/json")
        XCTAssertNil(served.headers.value(for: "Content-Length"))
        XCTAssertEqual(String(decoding: served.body, as: UTF8.self), #"{"error":"missing"}"#)
    }

    func testFilesDoNotOverwriteEachOtherAndNoResponseIsAnError() throws {
        let first = try MockMaker.make(from: flow(), in: folder), second = try MockMaker.make(from: flow(), in: folder)
        XCTAssertNotEqual(first.file, second.file)
        var pending = flow(); pending.response = nil
        XCTAssertThrowsError(try MockMaker.make(from: pending, in: folder))
    }

    /// End to end: the rule, put in the engine, answers with the mock instead of the server.
    func testEngineServesTheMock() async throws {
        let harness = try Harness(); try await harness.start()
        var captured = flow(path: "/mocked?x=1", body: #"{"from":"mock"}"#)
        captured.request.host = "upstream.test"; captured.request.port = harness.upstream.port; captured.request.scheme = "http"
        let mock = try MockMaker.make(from: captured, in: folder)
        try await harness.reconfigure { $0.mapLocal = RuleSet(isEnabled: true, rules: [mock.rule]) }
        let (status, body) = try await harness.get("/mocked?x=2")
        XCTAssertEqual(status, 200); XCTAssertEqual(body, #"{"from":"mock"}"#)
        await harness.stop()
    }
}
