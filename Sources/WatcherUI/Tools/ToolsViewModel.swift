import Foundation
import Observation
import WatcherCore

/// What the Tools window shows about each tool: which page is open, how many rules take effect, and which tools have a
/// rule that cannot work. Rule edits still go into `AppModel.settings`, which saves and applies them.
@MainActor @Observable
final class ToolsViewModel {
    @ObservationIgnored private let settings: SettingsEditor
    @ObservationIgnored private let router: WindowRouter
    @ObservationIgnored private let proxy: ProxyController

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
        let current = settings.value
        func matching<R: ToolRule>(_ set: RuleSet<R>, _ pattern: (R) -> MatchingRule) -> [String] {
            set.rules.filter(\.isEnabled).flatMap { ToolValidation.problems(pattern($0)) }
        }
        switch tool {
        case .block: return matching(current.blockList) { $0.matching }
        case .allow: return matching(current.allowList) { $0.matching }
        case .mapLocal: return matching(current.mapLocal) { $0.matching }
        case .mapRemote: return matching(current.mapRemote) { $0.matching }
        case .breakpoint: return matching(current.breakpoints) { $0.matching }
        case .scripting: return matching(current.scripting) { $0.matching }
        case .previewers: return matching(current.previewers) { $0.matching }
        case .protobuf: return matching(current.protobuf) { $0.matching }
        case .dns: return current.dnsSpoofing.rules.filter(\.isEnabled).flatMap { ToolValidation.problems($0) }
        case .reverse:
            let port = proxy.port
            return current.reverseProxy.rules.enumerated().filter(\.element.isEnabled).flatMap { index, rule in
                ToolValidation.problems(rule, proxyPort: port, others: current.reverseProxy.rules.enumerated().filter { $0.offset != index }.map(\.element))
            }
        case .certificates: return current.customCertificates.rules.filter(\.isEnabled).flatMap { ToolValidation.problems($0) }
        case .sslProxying, .throttling, .externalProxy: return []
        }
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
}
