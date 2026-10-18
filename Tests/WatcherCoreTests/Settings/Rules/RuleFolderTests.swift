import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RuleFolderTests {
    @Test
    func foldersGroupRulesAndSwitchThemTogether() {
        var set = RuleSet<BlockRule>(isEnabled: true, rules: [
            BlockRule(name: "a", matching: MatchingRule(pattern: "a")),
            BlockRule(name: "b", matching: MatchingRule(pattern: "b")),
            BlockRule(name: "c", matching: MatchingRule(pattern: "c")),
        ])
        set.rules[0].folder = "Ads"; set.rules[1].folder = "Ads"; set.rules[2].folder = "Tracking"
        #expect(set.folders == ["Ads", "Tracking"])

        set.setFolder("Ads", enabled: false)
        #expect(set.rules.map(\.isEnabled) == [false, false, true])
        #expect(set.active.map(\.name) == ["c"], "disabled folder rules no longer take effect")
        set.setFolder("Ads", enabled: true)
        #expect(set.active.count == 3)
        set.setFolder("Missing", enabled: false)
        #expect(set.active.count == 3, "an unknown folder changes nothing")
    }

    @Test
    func folderSurvivesSavingAndOlderRulesLoadWithoutOne() throws {
        var rule = MapLocalRule(name: "m", matching: MatchingRule(pattern: "*/m"), source: .file("/x"))
        rule.folder = "Checkout"
        let decoded = try JSONDecoder().decode(MapLocalRule.self, from: JSONEncoder().encode(rule))
        #expect(decoded.folder == "Checkout")

        let json = #"{"name":"x","isEnabled":true,"hidesRequest":false,"#
            + #""matching":{"pattern":"*","mode":"wildcard","methods":[],"includeSubpaths":false}}"#
        let old = try JSONDecoder().decode(BlockRule.self, from: Data(json.utf8))
        #expect(old.folder == nil)
    }

    @Test
    func everyRuleTypeCanBeFiled() {
        func filed(_ rule: some ToolRule) -> String? {
            var copy = rule; copy.folder = "F"; return copy.folder
        }
        #expect(filed(AllowRule(matching: MatchingRule())) == "F")
        #expect(filed(ScriptRule(matching: MatchingRule())) == "F")
        #expect(filed(DNSSpoofRule(host: "a", address: "b")) == "F")
        #expect(filed(ReverseProxyRule(localPort: 10000, remoteHost: "a")) == "F")
        #expect(filed(CustomCertificateRule(host: "a", role: .server, p12Path: "")) == "F")
        #expect(filed(ProtobufRule(matching: MatchingRule())) == "F")
        #expect(filed(PreviewerRule(matching: MatchingRule())) == "F")
    }
}
