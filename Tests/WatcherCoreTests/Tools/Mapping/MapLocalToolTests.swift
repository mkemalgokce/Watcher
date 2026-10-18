import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MapLocalToolTests {
    private let files = FileAccessFake()
    private let sleeper = SleepSpy()

    private func tool(source: MapLocalRule.Source = .file("/mocks/user.json"), delay: Int = 0) -> MapLocalTool {
        let rule = MapLocalRule(
            matching: MatchingRule(pattern: "api.example.com/v1/*"),
            source: source,
            delayMilliseconds: delay
        )
        return MapLocalTool(rules: [rule], read: files.access.read, sleep: sleeper.sleep)
    }

    private func answer(_ tool: MapLocalTool, path: String = "/v1/user") async -> ResponseRecord? {
        var request = RequestRecord.fixture(path: path)
        guard case let .respond(response) = await tool.intercept(request: &request) else { return nil }
        return response
    }

    @Test
    func aMatchingRequestIsAnsweredFromTheFile() async {
        files.write(Data(#"{"id":1}"#.utf8), to: "/mocks/user.json")
        let response = await answer(tool())
        #expect(response?.status == 200)
        #expect(response?.headers.value(for: "Content-Type")?.hasPrefix("application/json") == true)
        #expect(response?.body == Data(#"{"id":1}"#.utf8))
    }

    @Test
    func aRequestTheRuleDoesNotMatchIsForwarded() async {
        var request = RequestRecord.fixture(path: "/v2/user")
        guard case .forward = await tool().intercept(request: &request) else {
            Issue.record("expected the request to be forwarded"); return
        }
        #expect(sleeper.durations.isEmpty)
    }

    @Test
    func aMissingFileIsAnswered404NamingIt() async {
        let response = await answer(tool())
        #expect(response?.status == 404)
        #expect(response?.body == Data("Watcher Map Local: file not found: /mocks/user.json".utf8))
    }

    @Test
    func aTildeInTheFilePathMeansTheHomeFolder() async {
        files.write(Data("hi".utf8), to: NSHomeDirectory() + "/mock.txt")
        #expect(await answer(tool(source: .file("~/mock.txt")))?.body == Data("hi".utf8))
    }

    @Test(arguments: [(0, [] as [Duration]), (250, [.milliseconds(250)])])
    func theRuleDelayIsWaitedBeforeAnswering(delay: Int, waits: [Duration]) async {
        files.write(Data(), to: "/mocks/user.json")
        _ = await answer(tool(delay: delay))
        #expect(sleeper.durations == waits)
    }

    @Test
    func aDirectoryPathThatEscapesIsRefused() async {
        let response = await answer(tool(source: .directory("/mocks")), path: "/v1/%2e%2e/%2e%2e/etc/passwd")
        #expect(response?.status == 403)
    }

    @Test(arguments: ["/static/../../etc/passwd", "/static/%2e%2e/%2e%2e/etc/passwd"])
    func directoryRefusesTraversal(path: String) {
        let escape = RequestRecord.fixture(host: "a.com", path: path)
        let directory = FileManager.default.temporaryDirectory.path
        #expect(MapLocalTool.resolve(request: escape, pattern: "a.com/static/*", directory: directory) == nil)
    }

    @Test
    func directoryServesTheFileNamedByThePath() {
        let fine = RequestRecord.fixture(host: "a.com", path: "/static/app.js?v=1")
        let directory = FileManager.default.temporaryDirectory.path
        let resolved = MapLocalTool.resolve(request: fine, pattern: "a.com/static/*", directory: directory)
        #expect(resolved?.lastPathComponent == "app.js")
    }
}
