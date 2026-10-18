import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ToolFactoryTests {
    private static let everything: WatcherSettings = {
        var settings = WatcherSettings()
        let matching = MatchingRule()
        settings.allowList = RuleSet(isEnabled: true, rules: [AllowRule(matching: matching)])
        settings.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: matching)])
        settings.mapRemote = RuleSet(
            isEnabled: true, rules: [MapRemoteRule(matching: matching, destination: .init(host: "x.test"))]
        )
        settings.mapLocal = RuleSet(isEnabled: true, rules: [MapLocalRule(matching: matching, source: .file("/x"))])
        settings.noCaching = true
        settings.scripting = RuleSet(isEnabled: true, rules: [ScriptRule(matching: matching)])
        settings.breakpoints = RuleSet(isEnabled: true, rules: [BreakpointRule(matching: matching)])
        settings.throttle.isEnabled = true
        return settings
    }()

    private func names(_ settings: WatcherSettings) -> [String] {
        ToolFactory.makeTools(from: settings, breakpoints: BreakpointCenter(), log: { _ in }).map(\.name)
    }

    @Test
    func toolsRunGatekeepersFirstThenRewritersThenObservers() {
        #expect(names(Self.everything) == [
            "Allow List", "Block List", "Map Remote", "Map Local", "No Caching", "Scripting", "Breakpoint",
            "Network Throttling",
        ])
    }

    @Test
    func nothingEnabledMakesNoTools() {
        #expect(names(WatcherSettings()).isEmpty)
    }

    @Test(arguments: [
        \WatcherSettings.allowList.isEnabled, \.blockList.isEnabled, \.mapRemote.isEnabled, \.mapLocal.isEnabled,
    ])
    func aSwitchedOffRuleSetMakesNoTool(switchedOff: WritableKeyPath<WatcherSettings, Bool>) {
        var settings = Self.everything
        let before = names(settings).count
        settings[keyPath: switchedOff] = false
        #expect(names(settings).count == before - 1)
    }

    @Test
    func aRuleSetWithOnlyDisabledRulesMakesNoTool() {
        var settings = Self.everything
        settings.blockList.rules[0].isEnabled = false
        #expect(!names(settings).contains("Block List"))
    }

    @Test
    func aDisabledThrottleMakesNoTool() {
        var settings = Self.everything
        settings.throttle.isEnabled = false
        #expect(names(settings).last == "Breakpoint")
    }
}
