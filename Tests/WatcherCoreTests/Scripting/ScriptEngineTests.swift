import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct ScriptEngineTests {
    private let logged = LockedBox<[String]>([])

    private func engine(_ source: String, timeout: Duration = .seconds(10)) -> ScriptEngine {
        ScriptEngine(source: source, log: { [logged] line in logged.mutate { $0.append(line) } }, timeout: timeout)
    }

    @Test(arguments: [
        ("function onRequest() {}", true, false),
        ("function onResponse() {}", false, true),
        ("var onRequest = 1;", false, false),
    ])
    func theHooksAScriptDefinesAreKnown(source: String, onRequest: Bool, onResponse: Bool) {
        let engine = engine(source)
        #expect(engine.definesOnRequest == onRequest)
        #expect(engine.definesOnResponse == onResponse)
    }

    @Test(arguments: [
        ("function f(a, b) { return a + b; }", "3"),
        ("async function f(a, b) { return { sum: a + b }; }", #"{"sum":3}"#),
        ("function f() {}", "null"),
    ])
    func aCallAnswersWithTheAwaitedResultAsJSON(source: String, json: String) async throws {
        #expect(try await engine(source).call("f", argumentsJSON: "[1, 2]") == json)
    }

    @Test(arguments: [
        "function f() { throw new Error('boom'); }",
        "function f() { return Promise.reject(new Error('boom')); }",
    ])
    func aThrowOrRejectionFailsTheCallWithItsMessage(source: String) async {
        await #expect(throws: ScriptError(description: "Error: boom")) {
            try await engine(source).call("f", argumentsJSON: "[]")
        }
    }

    @Test
    func aPromiseThatNeverSettlesTimesOut() async {
        let engine = engine("function f() { return new Promise(function () {}); }", timeout: .milliseconds(20))
        await #expect(throws: ScriptError(description: "f did not finish within 0.02 seconds")) {
            try await engine.call("f", argumentsJSON: "[]")
        }
    }

    @Test
    func anEndlessSynchronousLoopTimesOutAndLeavesTheEngineUsable() async throws {
        let engine = engine("function spin() { for (;;) {} } function f() { return 1; }", timeout: .milliseconds(50))
        await #expect(throws: ScriptError(description: "spin did not finish within 0.05 seconds")) {
            try await engine.call("spin", argumentsJSON: "[]")
        }
        #expect(try await engine.call("f", argumentsJSON: "[]") == "1")
    }

    @Test
    func consoleOutputAndScriptErrorsReachTheLog() async throws {
        let talking = engine("function f() { console.log('hello'); console.error('bad'); }")
        _ = try await talking.call("f", argumentsJSON: "[]")
        _ = engine("this is not javascript")
        #expect(logged.value.prefix(2) == ["hello", "bad"])
        #expect(logged.value.last?.hasPrefix("script error: SyntaxError") == true)
    }

    @Test
    func base64HelpersAreAvailable() async throws {
        let engine = engine("function f(s) { return [btoa(s), atob(btoa(s))]; }")
        #expect(try await engine.call("f", argumentsJSON: #"["hi"]"#) == #"["aGk=","hi"]"#)
    }
}
