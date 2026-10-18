import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Which tools the status bar and the toolbar badge count as changing traffic.
@Suite(.tags(.unit))
struct ToolsModelTests {
    @Test
    func nothingIsActiveByDefault() {
        #expect(ToolPage.activeNames(in: WatcherSettings()).isEmpty)
    }

    @Test
    func everyActiveToolIsNamedInTheStatusBarOrder() {
        let settings = WatcherSettings.everythingChanged
        #expect(ToolPage.activeNames(in: settings) == [
            "Map Local", "Map Remote", "Block List", "Allow List", "Breakpoints", "Scripting", "DNS Spoofing",
            "Reverse Proxy", "Throttling", "External Proxy", "No Caching",
        ])
    }

    @Test
    func aToolWithOnlyDisabledRulesIsNotNamed() {
        var settings = WatcherSettings()
        let any = MatchingRule(pattern: "*")
        settings.blockList = RuleSet(isEnabled: true, rules: [BlockRule(isEnabled: false, matching: any)])
        settings.mapLocal = RuleSet(isEnabled: false, rules: [MapLocalRule(matching: any, source: .file("/a"))])
        #expect(ToolPage.activeNames(in: settings).isEmpty)
    }

    @Test
    func noCachingIsNamedOnItsOwn() {
        var settings = WatcherSettings()
        settings.noCaching = true
        #expect(ToolPage.activeNames(in: settings) == ["No Caching"])
    }

    @Test
    func theToolbarCountsTheRulesOfTheToolsTheStatusBarNames() {
        let settings = WatcherSettings.everythingChanged
        let named = ToolPage.allCases.filter { ToolPage.activeNames(in: settings).contains($0.rawValue) }
        #expect(ToolPage.activeRuleCount(in: settings) == named.reduce(0) { $0 + $1.activeCount(in: settings) })
        #expect(ToolPage.activeRuleCount(in: WatcherSettings()) == 0)
    }

    @Test
    func toolsThatOnlyInspectAreNotCountedAsChangingTraffic() {
        var settings = WatcherSettings()
        let any = MatchingRule(pattern: "*")
        settings.sslProxying.include = ["*"]
        settings.protobuf = RuleSet(isEnabled: true, rules: [ProtobufRule(matching: any)])
        settings.previewers = RuleSet(isEnabled: true, rules: [PreviewerRule(matching: any)])
        let certificate = CustomCertificateRule(host: "a.example", role: .server, p12Path: "/a.p12")
        settings.customCertificates = RuleSet(isEnabled: true, rules: [certificate])
        #expect(ToolPage.activeNames(in: settings).isEmpty)
        #expect(ToolPage.activeRuleCount(in: settings) == 0)
    }
}
