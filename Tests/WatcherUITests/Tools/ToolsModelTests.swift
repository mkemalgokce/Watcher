import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Which tools the status bar names as changing traffic.
@Suite(.tags(.unit))
struct ToolsModelTests {
    @Test
    func nothingIsActiveByDefault() {
        #expect(ToolsView.Tool.activeNames(in: WatcherSettings()).isEmpty)
    }

    @Test
    func everyActiveToolIsNamedInTheStatusBarOrder() {
        let settings = WatcherSettings.everythingChanged
        #expect(ToolsView.Tool.activeNames(in: settings) == [
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
        #expect(ToolsView.Tool.activeNames(in: settings).isEmpty)
    }

    @Test
    func noCachingIsNamedOnItsOwn() {
        var settings = WatcherSettings()
        settings.noCaching = true
        #expect(ToolsView.Tool.activeNames(in: settings) == ["No Caching"])
    }
}
