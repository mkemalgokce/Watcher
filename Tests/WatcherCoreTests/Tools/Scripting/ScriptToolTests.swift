import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct ScriptToolTests {
    private let logged = LockedBox<[String]>([])
    private let files = FileAccessFake()

    private func tool(_ source: String, pattern: String = "*", timeout: Duration = .seconds(10)) -> ScriptTool {
        ScriptTool(
            rules: [ScriptRule(matching: MatchingRule(pattern: pattern), source: source)],
            log: { [logged] line in logged.mutate { $0.append(line) } },
            timeout: timeout,
            read: files.access.read
        )
    }

    private func edited(_ request: RequestRecord, by source: String) async -> RequestRecord {
        var request = request
        _ = await tool(source).intercept(request: &request)
        return request
    }

    private func edited(_ response: ResponseRecord, by source: String) async -> ResponseRecord {
        var response = response
        await tool(source).intercept(response: &response, for: .fixture())
        return response
    }

    @Test(arguments: [
        ("function onRequest(c, u, r) { return r; }", true, false),
        ("function onResponse(c, u, q, r) { return r; }", false, true),
    ])
    func theHooksDecideWhetherBodiesMustBeBuffered(source: String, needsRequestBody: Bool, inspectsResponses: Bool) {
        #expect(tool(source).needsRequestBody == needsRequestBody)
        #expect(tool(source).inspectsResponses == inspectsResponses)
    }

    @Test
    func editedHeadersKeepTheirOrderAndCasingAndNewOnesFollow() async {
        let request = RequestRecord.fixture(headers: [Header("X-First", "1"), Header("accept", "*/*")])
        let script = """
        function onRequest(c, u, r) { r.headers['accept'] = 'text/html'; r.headers['X-New'] = 'n'; return r; }
        """
        let result = await edited(request, by: script)
        #expect(result.headers == [Header("X-First", "1"), Header("accept", "text/html"), Header("X-New", "n")])
    }

    @Test
    func editedQueriesRewriteThePathInNameOrder() async {
        let script = "function onRequest(c, u, r) { r.queries = { z: '1', a: 'b c' }; return r; }"
        #expect(await edited(RequestRecord.fixture(path: "/search?q=old"), by: script).path == "/search?a=b%20c&z=1")
    }

    @Test
    func removingEveryQueryLeavesThePathBare() async {
        let script = "function onRequest(c, u, r) { r.queries = {}; return r; }"
        #expect(await edited(RequestRecord.fixture(path: "/search?q=old"), by: script).path == "/search")
    }

    @Test
    func aJSONBodyIsSeenAsAnObjectAndCanBeReplacedByOne() async {
        let request = RequestRecord.fixture(
            method: "POST",
            headers: [Header("Content-Type", "application/json")],
            body: Data(#"{"n":1}"#.utf8)
        )
        let script = "function onRequest(c, u, r) { r.body = { n: r.body.n + 1 }; r.method = 'PUT'; return r; }"
        let result = await edited(request, by: script)
        #expect(result.body == Data(#"{"n":2}"#.utf8))
        #expect(result.method == "PUT")
    }

    @Test
    func aJSONArrayBodyCanBeReturned() async {
        let script = "function onResponse(c, u, q, r) { r.body = [1, 2]; return r; }"
        #expect(await edited(ResponseRecord.fixture(), by: script).body == Data("[1,2]".utf8))
    }

    @Test
    func aBinaryBodyIsLeftAlone() async {
        let binary = Data([0xFF, 0xFE, 0x00])
        let script = "function onRequest(c, u, r) { r.headers['X-Seen'] = String(r.body); return r; }"
        let result = await edited(RequestRecord.fixture(body: binary), by: script)
        #expect(result.body == binary)
        #expect(result.headers.value(for: "X-Seen") == "null")
    }

    @Test
    func aResponseStatusAndBodyCanBeEdited() async {
        let script = "function onResponse(c, u, q, r) { r.statusCode = 201; r.body = 'made'; return r; }"
        let result = await edited(ResponseRecord.fixture(status: 200), by: script)
        #expect(result.status == 201)
        #expect(result.body == Data("made".utf8))
    }

    @Test
    func aBodyFilePathReplacesTheResponseBodyWithThatFile() async {
        files.write(Data("from disk".utf8), to: "/mocks/answer.txt")
        let script = "function onResponse(c, u, q, r) { r.bodyFilePath = '/mocks/answer.txt'; return r; }"
        #expect(await edited(ResponseRecord.fixture(), by: script).body == Data("from disk".utf8))
    }

    @Test
    func anUnreadableBodyFileKeepsTheBody() async {
        let script = "function onResponse(c, u, q, r) { r.bodyFilePath = '/mocks/missing.txt'; return r; }"
        let response = ResponseRecord.fixture(body: Data("kept".utf8))
        #expect(await edited(response, by: script).body == Data("kept".utf8))
    }

    @Test(arguments: [
        "function onRequest() { throw new Error('boom'); }",
        "function onRequest() { return Promise.reject('boom'); }",
    ])
    func aFailingScriptIsLoggedAndTheRequestForwardedUnchanged(source: String) async {
        let request = RequestRecord.fixture(path: "/a")
        var copy = request
        guard case .forward = await tool(source).intercept(request: &copy) else {
            Issue.record("expected the request to be forwarded"); return
        }
        #expect(copy == request)
        #expect(logged.value.contains { $0.hasPrefix("onRequest failed for \(request.url)") })
    }

    @Test
    func aScriptThatNeverAnswersTimesOutAndForwardsUnchanged() async {
        let request = RequestRecord.fixture(path: "/a")
        var copy = request
        let stuck = tool("function onRequest() { return new Promise(function () {}); }", timeout: .milliseconds(20))
        _ = await stuck.intercept(request: &copy)
        #expect(copy == request)
        #expect(logged.value.contains { $0.contains("did not finish within") })
    }

    @Test
    func aRequestTheRuleDoesNotMatchIsNotScripted() async {
        let script = "function onRequest(c, u, r) { r.method = 'DELETE'; return r; }"
        var request = RequestRecord.fixture(path: "/a")
        _ = await tool(script, pattern: "*/other").intercept(request: &request)
        #expect(request.method == "GET")
    }
}
