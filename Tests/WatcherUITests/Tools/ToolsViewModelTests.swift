import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The Tools sidebar: counts, problem marks and the spoken summary come from the view model.
@MainActor
@Suite(.tags(.unit))
struct ToolsViewModelTests {
    @Test
    func summariesCountRulesAndFlagTheOnesThatNeedAttention() throws {
        let model = try AppModel.test()
        let tools = ToolsViewModel(settings: model.settings, router: model.router, proxy: model.proxy)
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
        #expect(model.router.toolsSelection == .dns, "the page choice is the router's, so menus can open Tools on it")
    }

    @Test
    func twoIdenticalReverseProxyRulesAreFlaggedInTheListAndInTheirForms() throws {
        let model = try AppModel.test()
        let tools = ToolsViewModel(settings: model.settings, router: model.router, proxy: model.proxy)
        let rule = ReverseProxyRule(localPort: 9191, remoteHost: "example.com")
        model.settings.reverseProxy = RuleSet(isEnabled: true, rules: [rule, rule])
        #expect(tools.problems(.reverse).count == 2)
        #expect(!tools.problems(.reverse, ruleAt: 0).isEmpty, "the form of a duplicated rule says so too")
        #expect(!tools.problems(.reverse, ruleAt: 1).isEmpty)
    }

    @Test
    func aSwitchedOffRuleStillShowsItsProblemsInItsForm() throws {
        let model = try AppModel.test()
        let tools = ToolsViewModel(settings: model.settings, router: model.router, proxy: model.proxy)
        model.settings.dnsSpoofing = RuleSet(isEnabled: true, rules: [
            DNSSpoofRule(isEnabled: false, host: "api.example.com", address: "nope"),
        ])
        #expect(tools.problems(.dns).isEmpty)
        #expect(!tools.problems(.dns, ruleAt: 0).isEmpty)
    }

    @Test(arguments: ToolsView.Tool.allCases)
    func aRuleThatIsGoneHasNoProblems(tool: ToolsView.Tool) throws {
        let model = try AppModel.test()
        let tools = ToolsViewModel(settings: model.settings, router: model.router, proxy: model.proxy)
        #expect(tools.problems(tool, ruleAt: 0).isEmpty)
        #expect(tools.problems(tool, ruleAt: -1).isEmpty)
    }
}
