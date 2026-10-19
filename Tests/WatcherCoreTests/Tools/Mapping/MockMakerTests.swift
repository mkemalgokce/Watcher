import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MockMakerTests {
    private let folder = URL(fileURLWithPath: "/fake-home/.watcher/mocks")
    private let files = FileAccessFake()

    private func make(_ flow: Flow) throws -> MockMaker.Mock {
        try MockMaker.make(from: flow, in: folder, files: files.access)
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
        let mock = try make(flow())
        #expect(mock.file.pathExtension == "json")
        #expect(mock.file.path == "/fake-home/.watcher/mocks/api.example.com/get-v1_users.json")
        #expect(files.contents(of: mock.file.path) == Data(#"{"a":1}"#.utf8))
        let matcher = mock.rule.matching.compile()
        #expect(matcher.matches(.fixture(method: "GET", path: "/v1/users")))
        #expect(matcher.matches(.fixture(method: "GET", path: "/v1/users?page=2")))
        #expect(!matcher.matches(.fixture(method: "POST", path: "/v1/users")))
        #expect(!matcher.matches(.fixture(method: "GET", path: "/v1/users/42")))
        #expect(!matcher.matches(.fixture(method: "GET", host: "evil-api.example.com", path: "/v1/users")))
    }

    /// The same URL rule a breakpoint gets: a root mock also answers the bare host, and a WebSocket handshake matches.
    @Test
    func aRootMockMatchesTheBareHostAndAnyScheme() throws {
        let root = Flow.fixture(request: .fixture(path: "/"), response: .fixture(), state: .pending)
        let matcher = try make(root).rule.matching.compile()
        #expect(matcher.matches(.fixture(method: "GET", path: "")))
        #expect(matcher.matches(.fixture(method: "GET", scheme: "wss", path: "/")))
    }

    /// A 404 keeps its status: the file is a raw HTTP message that Map Local serves as it is.
    @Test
    func non200KeepsStatusAndHeadersButDropsStaleLengths() throws {
        let mock = try make(flow(status: 404, body: #"{"error":"missing"}"#))
        #expect(mock.file.pathExtension == "txt")
        let served = try HTTPMessageFile.response(
            from: #require(files.contents(of: mock.file.path)),
            fileName: mock.file.lastPathComponent
        )
        #expect(served.status == 404)
        #expect(served.headers.value(for: "Content-Type") == "application/json")
        #expect(served.headers.value(for: "Content-Length") == nil)
        #expect(String(bytes: served.body, encoding: .utf8) == #"{"error":"missing"}"#)
    }

    @Test
    func filesDoNotOverwriteEachOtherAndNoResponseIsAnError() throws {
        let first = try make(flow()), second = try make(flow())
        #expect(first.file != second.file)
        var pending = flow(); pending.response = nil
        #expect(throws: (any Error).self) { try make(pending) }
    }

    @Test
    func aTakenNameGetsTheNextFreeNumber() throws {
        let directory = "/fake-home/.watcher/mocks/api.example.com"
        files.write(Data(), to: "\(directory)/get-v1_users.json")
        files.write(Data(), to: "\(directory)/get-v1_users-2.json")
        #expect(try make(flow()).file.lastPathComponent == "get-v1_users-3.json")
    }

    @Test(arguments: [FileAccessFake.Operation.createDirectory, .writeAtomically])
    func aFolderOrFileThatCannotBeWrittenIsReported(_ operation: FileAccessFake.Operation) {
        files.fail(operation)
        #expect(throws: FileAccessFake.Failure(operation: operation)) { try make(flow()) }
    }
}
