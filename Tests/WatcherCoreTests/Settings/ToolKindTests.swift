import Testing
@testable import WatcherCore

@Suite(.tags(.unit))
struct ToolKindTests {
    @Test
    func everyToolHasItsOwnName() {
        #expect(Set(ToolKind.allCases.map(\.rawValue)).count == ToolKind.allCases.count)
    }

    @Test(arguments: ToolKind.allCases)
    func switchingAToolOnAndOffTouchesOnlyThatTool(kind: ToolKind) {
        var settings = WatcherSettings()
        settings[keyPath: kind.switchPath] = true
        for other in ToolKind.allCases {
            #expect(settings[keyPath: other.switchPath] == (other == kind), "\(other) after switching on \(kind)")
        }
        settings[keyPath: kind.switchPath] = false
        #expect(ToolKind.allCases.allSatisfy { !settings[keyPath: $0.switchPath] })
    }

    @Test
    func aRuleToolSaysItsStateAndRuleCount() {
        var settings = WatcherSettings()
        settings.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: MatchingRule())])
        let local = MapLocalRule(matching: MatchingRule(), source: .file("x"))
        settings.mapLocal = RuleSet(isEnabled: false, rules: [local])
        #expect(ToolKind.blockList.summary(in: settings) == "on, 1 rule(s)")
        #expect(ToolKind.mapLocal.summary(in: settings) == "off, 1 rule(s)")
        #expect(ToolKind.allowList.summary(in: settings) == "off, 0 rule(s)")
    }

    @Test
    func theNetworkConditionNamesItsProfileOnlyWhileOn() {
        var settings = WatcherSettings()
        #expect(ToolKind.networkCondition.summary(in: settings) == "off")
        settings.throttle.isEnabled = true
        settings.throttle.profile = NetworkProfile.presets[0]
        #expect(ToolKind.networkCondition.summary(in: settings) == "on (3G)")
    }

    @Test(arguments: [ToolKind.noCaching, .externalProxy])
    func aToolWithoutRulesSaysOnlyItsState(kind: ToolKind) {
        var settings = WatcherSettings()
        #expect(kind.summary(in: settings) == "off")
        settings[keyPath: kind.switchPath] = true
        #expect(kind.summary(in: settings) == "on")
    }
}
