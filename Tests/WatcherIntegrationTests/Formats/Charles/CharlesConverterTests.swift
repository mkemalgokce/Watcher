import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// Runs against a real Charles Proxy when one is installed.
@Suite(
    .timeLimit(.minutes(1)),
    .tags(.integration, .externalTool),
    .enabled(
        if: FileManager.default.isExecutableFile(atPath: CharlesConverter.defaultExecutable.path),
        "needs Charles"
    )
)
struct CharlesConverterTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(prefix: "watcher-charles")
    }

    @Test
    func binarySessionsWrittenByARealCharlesAreReadBack() async throws {
        var post = Flow.fixture(
            sequence: 2,
            request: .fixture(
                method: "POST",
                path: "/v1/login?x=1",
                headers: [Header("Content-Type", "application/json")],
                body: Data(#"{"user":"ada"}"#.utf8)
            ),
            response: .fixture(
                status: 401,
                headers: [Header("Content-Type", "application/json")],
                body: Data(#"{"error":"nope"}"#.utf8)
            )
        )
        post.duration = 0.2
        var get = Flow.fixture(
            request: .fixture(host: "example.com"),
            response: .fixture(headers: [Header("Content-Type", "text/html")], body: Data("<h1>hi</h1>".utf8))
        )
        get.duration = 0.1

        let har = directory.appending("in.har")
        try HAR.export([get, post]).write(to: har)
        // Charles itself writes the binary formats.
        let chls = directory.appending("session.chls"), chlz = directory.appending("session.chlz")
        try convert(har, to: chls)
        try convert(chls, to: chlz)

        for session in [chls, chlz] {
            let flows = try await CharlesConverter.flows(from: session)
            #expect(flows.count == 2, "\(session.lastPathComponent)")
            let byPath = Dictionary(uniqueKeysWithValues: flows.map { ($0.request.path, $0) })
            #expect(byPath["/"]?.response?.status == 200, "\(session.lastPathComponent)")
            #expect(byPath["/v1/login?x=1"]?.request.method == "POST")
            #expect(byPath["/v1/login?x=1"]?.response?.status == 401)
            #expect(byPath["/v1/login?x=1"]?.request.body == Data(#"{"user":"ada"}"#.utf8))
            #expect(String(bytes: byPath["/"]?.response?.body ?? Data(), encoding: .utf8) == "<h1>hi</h1>")
        }
    }

    @Test
    func realChlsjFilesImportWithDefaultPortsAndOffsetTimestamps() throws {
        var flow = Flow.fixture(
            request: .fixture(host: "example.com", path: "/a?b=1"),
            response: .fixture(headers: [Header("Content-Type", "text/plain")], body: Data("hello".utf8))
        )
        flow.duration = 0.25
        let har = directory.appending("in.har"), chlsj = directory.appending("real.chlsj")
        try HAR.export([flow]).write(to: har)
        try convert(har, to: chlsj)

        let imported = try CharlesSession.flows(from: Data(contentsOf: chlsj)).filter { $0.request.method != "CONNECT" }
        let first = try #require(imported.first)
        #expect(first.request.url == "https://example.com/a?b=1", "actualPort -1 must fall back to 443")
        #expect(first.response?.status == 200)
        #expect(String(bytes: first.response?.body ?? Data(), encoding: .utf8) == "hello")
        #expect(first.startedAt.timeIntervalSince1970 != 0)
    }

    @Test
    func aGarbageFileIsReportedNotSilentlyIgnored() async throws {
        let file = directory.appending("garbage.chls")
        try Data("this is not a charles session".utf8).write(to: file)
        let error = await #expect(throws: CharlesConverter.ConversionError.self) {
            _ = try await CharlesConverter.flows(from: file)
        }
        #expect(error.map { "\($0)" }?.contains("could not convert") == true, "\(String(describing: error))")
    }

    private func convert(_ input: URL, to output: URL) throws {
        let charles = ExternalTool(name: "Charles", candidates: [CharlesConverter.defaultExecutable.path])
        #expect(try charles.run(["convert", input.path, output.path]).status == 0)
    }
}
