import Foundation
import Observation
import WatcherCore

/// What the Tools window shows about each tool: which page is open, how many rules take effect, and which tools have a
/// rule that cannot work. Rule edits still go into `AppModel.settings`, which saves and applies them.
@MainActor @Observable
final class ToolsViewModel {
    @ObservationIgnored private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var selection: ToolsView.Tool {
        get { model.toolsSelection }
        set { model.toolsSelection = newValue }
    }

    func activeCount(_ tool: ToolsView.Tool) -> Int {
        tool.activeCount(in: model.settings)
    }

    /// Every problem in the tool's enabled rules (see ToolValidation).
    func problems(_ tool: ToolsView.Tool) -> [String] {
        let s = model.settings
        func matching<R: ToolRule>(_ set: RuleSet<R>, _ pattern: (R) -> MatchingRule) -> [String] {
            set.rules.filter(\.isEnabled).flatMap { ToolValidation.problems(pattern($0)) }
        }
        switch tool {
        case .block: return matching(s.blockList) { $0.matching }
        case .allow: return matching(s.allowList) { $0.matching }
        case .mapLocal: return matching(s.mapLocal) { $0.matching }
        case .mapRemote: return matching(s.mapRemote) { $0.matching }
        case .breakpoint: return matching(s.breakpoints) { $0.matching }
        case .scripting: return matching(s.scripting) { $0.matching }
        case .previewers: return matching(s.previewers) { $0.matching }
        case .protobuf: return matching(s.protobuf) { $0.matching }
        case .dns: return s.dnsSpoofing.rules.filter(\.isEnabled).flatMap { ToolValidation.problems($0) }
        case .reverse:
            let port = model.proxyPort
            return s.reverseProxy.rules.enumerated().filter(\.element.isEnabled).flatMap { index, rule in
                ToolValidation.problems(rule, proxyPort: port, others: s.reverseProxy.rules.enumerated().filter { $0.offset != index }.map(\.element))
            }
        case .certificates: return s.customCertificates.rules.filter(\.isEnabled).flatMap { ToolValidation.problems($0) }
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
