import Foundation
import WatcherCore

/// What the Tools window shows about each tool: which page is open, how many rules take effect, and which tools have a
/// rule that cannot work. Rule edits still go into `AppModel.settings`, which saves and applies them.
@MainActor
final class ToolsViewModel {
    private let settings: SettingsEditor
    private let router: WindowRouter
    private let proxy: ProxyController

    init(settings: SettingsEditor, router: WindowRouter, proxy: ProxyController) {
        self.settings = settings; self.router = router; self.proxy = proxy
    }

    var selection: ToolsView.Tool {
        get { router.toolsSelection }
        set { router.toolsSelection = newValue }
    }

    func activeCount(_ tool: ToolsView.Tool) -> Int {
        tool.activeCount(in: settings.value)
    }

    /// Every problem in the tool's enabled rules (see ToolValidation).
    func problems(_ tool: ToolsView.Tool) -> [String] {
        checkedRules(tool).filter(\.isEnabled).flatMap(\.problems)
    }

    /// What is wrong with one rule, switched on or not; its form shows this above the fields.
    func problems(_ tool: ToolsView.Tool, ruleAt index: Int) -> [String] {
        let rules = checkedRules(tool)
        return rules.indices.contains(index) ? rules[index].problems : []
    }

    /// For VoiceOver and the sidebar tooltip: "2 rules on", "Off", "1 rule needs attention".
    func summary(_ tool: ToolsView.Tool) -> String {
        let issues = problems(tool).count
        if issues > 0 {
            return issues == 1 ? "1 rule needs attention" : "\(issues) problems in rules"
        }
        let active = activeCount(tool)
        return active == 0 ? "Off" : active == 1 ? "1 rule on" : "\(active) rules on"
    }

    private struct CheckedRule {
        let isEnabled: Bool
        let problems: [String]
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func checkedRules(_ tool: ToolsView.Tool) -> [CheckedRule] { // one case per tool
        switch tool {
        case .block: check(\.blockList) { rule, _ in ToolValidation.problems(rule.matching) }
        case .allow: check(\.allowList) { rule, _ in ToolValidation.problems(rule.matching) }
        case .mapLocal: check(\.mapLocal) { rule, _ in ToolValidation.problems(rule.matching) }
        case .mapRemote: check(\.mapRemote) { rule, _ in ToolValidation.problems(rule.matching) }
        case .breakpoint: check(\.breakpoints) { rule, _ in ToolValidation.problems(rule.matching) }
        case .scripting: check(\.scripting) { rule, _ in ToolValidation.problems(rule.matching) }
        case .previewers: check(\.previewers) { rule, _ in ToolValidation.problems(rule.matching) }
        case .protobuf: check(\.protobuf) { rule, _ in ToolValidation.problems(rule.matching) }
        case .dns: check(\.dnsSpoofing) { rule, _ in ToolValidation.problems(rule) }
        case .certificates: check(\.customCertificates) { rule, _ in ToolValidation.problems(rule) }
        case .reverse: check(\.reverseProxy) { rule, others in
                ToolValidation.problems(rule, proxyPort: proxy.port, others: others)
            }
        case .sslProxying, .throttling, .externalProxy: []
        }
    }

    /// `problems` gets each rule with every other rule of its list, which a rule can clash with.
    private func check<Rule: ToolRule>(
        _ list: KeyPath<WatcherSettings, RuleSet<Rule>>,
        problems: (Rule, _ others: [Rule]) -> [String]
    ) -> [CheckedRule] {
        let rules = settings.value[keyPath: list].rules
        return rules.indices.map { index in
            let others = rules.indices.filter { $0 != index }.map { rules[$0] }
            return CheckedRule(isEnabled: rules[index].isEnabled, problems: problems(rules[index], others))
        }
    }
}
