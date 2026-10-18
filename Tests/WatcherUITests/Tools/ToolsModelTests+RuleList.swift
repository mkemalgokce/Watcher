import Testing
@testable import WatcherCore
@testable import WatcherUI

extension ToolsModelTests {
    /// Rule list editing in Tools: what is selected after each change.
    struct RuleList {
        private func rule(_ name: String) -> BlockRule {
            BlockRule(name: name, matching: MatchingRule(pattern: "\(name)/*"))
        }

        @Test
        func addSwitchesTheToolOnAndSelectsTheNewRule() {
            var set = RuleSet<BlockRule>()
            #expect(!set.isEnabled)
            #expect(set.add(rule("a")) == 0)
            #expect(set.isEnabled)
            #expect(set.add(rule("b")) == 1)
        }

        @Test
        func removeSelectsTheNeighbour() {
            var set = RuleSet<BlockRule>(isEnabled: true, rules: [rule("a"), rule("b"), rule("c")])
            #expect(set.remove(at: 1) == 1, "the next rule moves up into the selection")
            #expect(set.rules.map(\.name) == ["a", "c"])
            #expect(set.remove(at: 1) == 0, "removing the last selects the new last")
            #expect(set.remove(at: 0) == nil, "nothing left to select")
            #expect(set.remove(at: 5) == nil, "out of range on an empty list")
            var other = RuleSet<BlockRule>(isEnabled: true, rules: [rule("a")])
            #expect(other.remove(at: 9) == 0, "a stale index changes nothing")
            #expect(other.rules.count == 1)
        }

        @Test
        func duplicateInsertsAfterTheOriginal() {
            var set = RuleSet<BlockRule>(isEnabled: true, rules: [rule("a"), rule("b")])
            #expect(set.duplicate(at: 0) == 1)
            #expect(set.rules.map(\.name) == ["a", "a", "b"])
            #expect(set.duplicate(at: 7) == nil)
        }

        @Test
        func activeCountsIgnoreDisabledRulesAndTools() {
            var settings = WatcherSettings()
            let off = BlockRule(name: "off", isEnabled: false, matching: MatchingRule(pattern: "*"))
            settings.blockList = RuleSet(isEnabled: true, rules: [rule("a"), off])
            #expect(ToolPage.block.activeCount(in: settings) == 1)
            settings.blockList.isEnabled = false
            #expect(ToolPage.block.activeCount(in: settings) == 0)
            settings.throttle.isEnabled = true
            #expect(ToolPage.throttling.activeCount(in: settings) == 1)
        }
    }
}
