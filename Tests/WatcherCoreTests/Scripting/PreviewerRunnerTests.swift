import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct PreviewerRunnerTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test
    func scriptsDecodeBinaryBodiesAndReportFailures() async throws {
        let engine = try WatcherEngine(directory: directory.url)
        let b64 = MatchingRule(pattern: "*/b64")
        try engine.settings.update {
            $0.previewers = RuleSet(isEnabled: true, rules: [
                PreviewerRule(
                    name: "Base64",
                    matching: b64,
                    source: "function preview(m) { return atob(m.bodyBase64).toUpperCase(); }"
                ),
                PreviewerRule(
                    name: "Summary",
                    matching: b64,
                    source: "function preview(m) { return { status: m.status, size: m.bodyBase64.length }; }"
                ),
                PreviewerRule(
                    name: "Broken",
                    matching: b64,
                    source: "function preview(m) { throw new Error('boom'); }"
                ),
                PreviewerRule(
                    name: "Elsewhere",
                    matching: MatchingRule(pattern: "*/other"),
                    source: "function preview(m) { return 'no'; }"
                ),
            ])
        }
        let flow = Flow.fixture(
            request: .fixture(host: "a.com", path: "/b64"),
            response: .fixture(body: Data("hello".utf8)),
            state: .pending
        )
        let outputs = await engine.previews(for: flow)
        #expect(outputs.map(\.name) == ["Base64", "Summary", "Broken"])
        #expect(outputs[0].text == "HELLO")
        #expect(
            outputs[1].text.contains("\"status\" : 200") && outputs[1].text.contains("\"size\" : 8"),
            "\(outputs[1].text)"
        )
        #expect(
            outputs[2].text.hasPrefix("Previewer failed") && outputs[2].text.contains("boom"),
            "\(outputs[2].text)"
        )
    }
}
