import Foundation
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
        let tools = model.toolsViewModel()
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
        let tools = model.toolsViewModel()
        let rule = ReverseProxyRule(localPort: 9191, remoteHost: "example.com")
        model.settings.reverseProxy = RuleSet(isEnabled: true, rules: [rule, rule])
        #expect(tools.problems(.reverse).count == 2)
        #expect(!tools.problems(.reverse, ruleAt: 0).isEmpty, "the form of a duplicated rule says so too")
        #expect(!tools.problems(.reverse, ruleAt: 1).isEmpty)
    }

    @Test
    func aSwitchedOffRuleStillShowsItsProblemsInItsForm() throws {
        let model = try AppModel.test()
        let tools = model.toolsViewModel()
        model.settings.dnsSpoofing = RuleSet(isEnabled: true, rules: [
            DNSSpoofRule(isEnabled: false, host: "api.example.com", address: "nope"),
        ])
        #expect(tools.problems(.dns).isEmpty)
        #expect(!tools.problems(.dns, ruleAt: 0).isEmpty)
    }

    @Test(arguments: ToolPage.allCases)
    func aRuleThatIsGoneHasNoProblems(tool: ToolPage) throws {
        let model = try AppModel.test()
        let tools = model.toolsViewModel()
        #expect(tools.problems(tool, ruleAt: 0).isEmpty)
        #expect(tools.problems(tool, ruleAt: -1).isEmpty)
    }

    @Test
    func aCertificateFileTheFileSystemHoldsIsNotAProblem() throws {
        let files = FileAccessFake(files: ["/fake-home/certs/c.p12": Data()])
        let model = try AppModel(dependencies: .test(files: files))
        let tools = model.toolsViewModel()
        model.settings.customCertificates = RuleSet(isEnabled: true, rules: [
            CustomCertificateRule(host: "a.test", role: .client, p12Path: "~/certs/c.p12"),
            CustomCertificateRule(host: "b.test", role: .client, p12Path: "~/certs/missing.p12"),
        ])
        #expect(tools.problems(.certificates) == ["No file at ~/certs/missing.p12."])
        #expect(tools.summary(.certificates) == "1 rule needs attention")
        #expect(tools.problems(.certificates, ruleAt: 0).isEmpty)
    }
}
