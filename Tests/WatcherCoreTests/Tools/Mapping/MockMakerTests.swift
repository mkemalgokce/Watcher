import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MockMakerTests {
    private let directory: TemporaryDirectory
    private var folder: URL {
        directory.appending("mocks")
    }

    init() throws {
        directory = try TemporaryDirectory(prefix: "watcher-mocks")
    }

    private func flow(status: Int = 200, body: String = #"{"a":1}"#) -> Flow {
        .fixture(
            request: .fixture(path: "/v1/users?page=1"),
            response: .fixture(
                status: status,
                headers: [Header("Content-Type", "application/json"), Header("Content-Length", "7")],
                body: Data(body.utf8)
            ),
            state: .pending
        )
    }

    @Test
    func plainJSONFileAndRuleThatMatchesTheSamePathWithAnyQuery() throws {
        let mock = try MockMaker.make(from: flow(), in: folder)
        #expect(mock.file.pathExtension == "json")
        #expect(try Data(contentsOf: mock.file) == Data(#"{"a":1}"#.utf8))
        let matcher = mock.rule.matching.compile()
        #expect(matcher.matches(.fixture(method: "GET", path: "/v1/users")))
        #expect(matcher.matches(.fixture(method: "GET", path: "/v1/users?page=2")))
        #expect(!matcher.matches(.fixture(method: "POST", path: "/v1/users")))
        #expect(!matcher.matches(.fixture(method: "GET", path: "/v1/users/42")))
        #expect(!matcher.matches(.fixture(method: "GET", host: "evil-api.example.com", path: "/v1/users")))
    }

    /// A 404 keeps its status: the file is a raw HTTP message that Map Local serves as it is.
    @Test
    func non200KeepsStatusAndHeadersButDropsStaleLengths() throws {
        let mock = try MockMaker.make(from: flow(status: 404, body: #"{"error":"missing"}"#), in: folder)
        #expect(mock.file.pathExtension == "txt")
        let served = try HTTPMessageFile.response(
            from: Data(contentsOf: mock.file),
            fileName: mock.file.lastPathComponent
        )
        #expect(served.status == 404)
        #expect(served.headers.value(for: "Content-Type") == "application/json")
        #expect(served.headers.value(for: "Content-Length") == nil)
        #expect(String(bytes: served.body, encoding: .utf8) == #"{"error":"missing"}"#)
    }

    @Test
    func filesDoNotOverwriteEachOtherAndNoResponseIsAnError() throws {
        let first = try MockMaker.make(from: flow(), in: folder), second = try MockMaker.make(from: flow(), in: folder)
        #expect(first.file != second.file)
        var pending = flow(); pending.response = nil
        #expect(throws: (any Error).self) { try MockMaker.make(from: pending, in: folder) }
    }
}
