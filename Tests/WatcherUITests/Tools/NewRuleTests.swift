import Testing
import WatcherCore
@testable import WatcherUI

@Suite(.tags(.unit))
struct NewRuleTests {
    private static let matching: [(String, MatchingRule)] = [
        ("block", NewRule.block().matching),
        ("allow", NewRule.allow().matching),
        ("mapLocal", NewRule.mapLocal().matching),
        ("mapRemote", NewRule.mapRemote().matching),
        ("breakpoint", NewRule.breakpoint().matching),
        ("scripting", NewRule.scripting().matching),
        ("previewer", NewRule.previewer().matching),
        ("protobuf", NewRule.protobuf().matching),
    ]

    @Test(arguments: matching)
    func aNewURLRuleMatchesEverythingAndStartsWithoutProblems(tool: String, matching: MatchingRule) {
        #expect(matching.pattern == "*", "\(tool)")
        #expect(ToolValidation.problems(matching) == [], "\(tool)")
    }

    @Test
    func aNewDNSRuleIsAValidExample() {
        #expect(ToolValidation.problems(NewRule.dns()) == [])
    }

    @Test
    func aNewReverseProxyIsValidNextToTheProxyPort() {
        #expect(ToolValidation.problems(NewRule.reverseProxy(), proxyPort: 9090, others: []) == [])
    }

    @Test
    func aNewCertificateRuleAsksForTheFileUntilOneIsChosen() {
        let problems = ToolValidation.problems(NewRule.certificate(), fileExists: { _ in true }, homeDirectory: "/h")
        #expect(problems == ["Choose the .p12 file."])
    }
}
