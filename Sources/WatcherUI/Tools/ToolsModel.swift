import WatcherCore

/// Editing a rule list: every operation returns the row that should be selected afterwards, so the list never points
/// at a rule that is gone.
extension RuleSet {
    /// Appends `rule` and switches the tool on: a new rule should work without hunting for a second switch.
    mutating func add(_ rule: Rule) -> Int {
        rules.append(rule)
        isEnabled = true
        return rules.count - 1
    }

    /// Removes the rule at `index`; the next one (or the new last one) is selected, nil once the list is empty.
    mutating func remove(at index: Int) -> Int? {
        guard rules.indices.contains(index) else { return rules.isEmpty ? nil : min(index, rules.count - 1) }
        rules.remove(at: index)
        return rules.isEmpty ? nil : min(index, rules.count - 1)
    }

    /// Inserts a copy right after the original and selects the copy.
    mutating func duplicate(at index: Int) -> Int? {
        guard rules.indices.contains(index) else { return nil }
        rules.insert(rules[index], at: index + 1)
        return index + 1
    }
}

extension ToolsView.Tool {
    private static let statusBarOrder: [Self] = [
        .mapLocal, .mapRemote, .block, .allow, .breakpoint, .scripting, .dns, .reverse, .throttling, .externalProxy,
    ]

    /// The tools changing traffic now, by name, as the status bar lists them; No Caching is a setting of its own.
    static func activeNames(in settings: WatcherSettings) -> [String] {
        let tools = statusBarOrder.filter { $0.activeCount(in: settings) > 0 }.map(\.rawValue)
        return tools + (settings.noCaching ? ["No Caching"] : [])
    }

    /// Rules that take effect now, shown as a badge in the Tools sidebar; 0 hides the badge.
    func activeCount(in s: WatcherSettings) -> Int {
        switch self {
        case .sslProxying: s.sslProxying.include.count
        case .block: s.blockList.active.count
        case .allow: s.allowList.active.count
        case .mapLocal: s.mapLocal.active.count
        case .mapRemote: s.mapRemote.active.count
        case .breakpoint: s.breakpoints.active.count
        case .scripting: s.scripting.active.count
        case .throttling: s.throttle.isEnabled ? 1 : 0
        case .dns: s.dnsSpoofing.active.count
        case .reverse: s.reverseProxy.active.count
        case .externalProxy: s.externalProxy.isEnabled ? 1 : 0
        case .protobuf: s.protobuf.active.count
        case .previewers: s.previewers.active.count
        case .certificates: s.customCertificates.active.count
        }
    }
}
