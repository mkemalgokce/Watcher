import Testing
@testable import WatcherCore
@testable import WatcherUI

/// The Tools sidebar: counts, problem marks and the spoken summary come from the view model.
@MainActor
struct ToolsViewModelTests {
    @Test
    func summariesAndProblems() {
        let model = AppModel(listening: false)
        let tools = ToolsViewModel(model: model)
        #expect(tools.summary(.block) == "Off")

        let ads = BlockRule(name: "ads", matching: MatchingRule(pattern: "ads.example.com/*"))
        model.settings.blockList = RuleSet(isEnabled: true, rules: [ads])
        #expect(tools.summary(.block) == "1 rule on")
        #expect(tools.problems(.block).isEmpty)

        let unusable = DNSSpoofRule(host: "api.example.com", address: "nope")
        model.settings.dnsSpoofing = RuleSet(isEnabled: true, rules: [unusable])
        #expect(tools.summary(.dns) == "1 rule needs attention")
        model.settings.dnsSpoofing.rules[0].isEnabled = false
        #expect(tools.problems(.dns).isEmpty, "a switched-off rule is not reported")

        model.settings.reverseProxy = RuleSet(isEnabled: true, rules: [
            ReverseProxyRule(localPort: 9191, remoteHost: "a"),
            ReverseProxyRule(localPort: 9191, remoteHost: "b"),
        ])
        #expect(tools.problems(.reverse).count == 2, "both rules on one port are flagged")

        tools.selection = .dns
        #expect(model.toolsSelection == .dns, "the page choice is the model's, so menus can open Tools on a page")
    }
}
