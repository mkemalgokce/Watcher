import Testing
import WatcherCore
@testable import WatcherUI

@Suite(.tags(.unit))
struct NamedMatchingRuleTests {
    private let pattern = MatchingRule(pattern: "api.example.com/*")

    private func names(_ make: (String) -> some NamedMatchingRule) -> [String] {
        [make("n").displayName, make("").displayName]
    }

    @Test
    func everyToolRuleIsListedByItsNameOrElseItsPattern() {
        let expected = ["n", "api.example.com/*"]
        #expect(names { BlockRule(name: $0, matching: pattern) } == expected)
        #expect(names { AllowRule(name: $0, matching: pattern) } == expected)
        #expect(names { MapLocalRule(name: $0, matching: pattern, source: .file("/f")) } == expected)
        #expect(names { MapRemoteRule(name: $0, matching: pattern, destination: .init()) } == expected)
        #expect(names { BreakpointRule(name: $0, matching: pattern) } == expected)
        #expect(names { ScriptRule(name: $0, matching: pattern) } == expected)
        #expect(names { PreviewerRule(name: $0, matching: pattern) } == expected)
        #expect(names { ProtobufRule(name: $0, matching: pattern) } == expected)
    }
}
