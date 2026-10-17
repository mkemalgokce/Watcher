import Foundation

extension RuleSet {
    func onlyEnabled() -> RuleSet {
        RuleSet(isEnabled: isEnabled, rules: rules.filter(\.isEnabled))
    }

    func appending(_ other: RuleSet) -> RuleSet {
        RuleSet(isEnabled: isEnabled || other.isEnabled, rules: rules + other.rules)
    }
}

/// One rule set of `WatcherSettings` with its rule type erased, so every tool fits one list.
struct RuleSetAccessor {
    let path: PartialKeyPath<WatcherSettings>
    let keepOnlyEnabled: (inout WatcherSettings) -> Void
    let append: (inout WatcherSettings, WatcherSettings) -> Void

    init(_ path: WritableKeyPath<WatcherSettings, RuleSet<some Any>>) {
        self.path = path
        keepOnlyEnabled = { $0[keyPath: path] = $0[keyPath: path].onlyEnabled() }
        append = { $0[keyPath: path] = $0[keyPath: path].appending($1[keyPath: path]) }
    }
}

extension WatcherSettings {
    /// Every tool's rules; `exported` and `importing` walk this list.
    static var ruleSets: [RuleSetAccessor] {
        [
            RuleSetAccessor(\.allowList), RuleSetAccessor(\.blockList),
            RuleSetAccessor(\.mapLocal), RuleSetAccessor(\.mapRemote),
            RuleSetAccessor(\.breakpoints), RuleSetAccessor(\.scripting),
            RuleSetAccessor(\.dnsSpoofing), RuleSetAccessor(\.reverseProxy),
            RuleSetAccessor(\.protobuf), RuleSetAccessor(\.customCertificates), RuleSetAccessor(\.previewers),
        ]
    }
}

/// Rule import/export semantics shared by the app and CLI.
public extension WatcherSettings {
    enum ExportMode: String, Sendable { case all, enabledRules }
    enum ImportMode: String, Sendable { case append, override }

    func exported(_ mode: ExportMode) -> WatcherSettings {
        guard mode == .enabledRules else { return self }
        var copy = self
        Self.ruleSets.forEach { $0.keepOnlyEnabled(&copy) }
        return copy
    }

    /// `override` replaces everything; `append` adds the incoming rules and keeps this machine's scalar settings.
    func importing(_ incoming: WatcherSettings, mode: ImportMode) -> WatcherSettings {
        guard mode == .append else { return incoming }
        var copy = self
        Self.ruleSets.forEach { $0.append(&copy, incoming) }
        return copy
    }

    /// Replaces only the tool rule lists (Block/Allow, Map Local/Remote, Breakpoints, Scripting, DNS, Reverse Proxy) with `incoming`'s and keeps
    /// everything else (port, SSL Proxying, SOCKS, certificates, ...). Used by imports from other tools, which know nothing about those settings.
    func replacingToolRules(with incoming: WatcherSettings) -> WatcherSettings {
        var copy = self
        copy.allowList = incoming.allowList; copy.blockList = incoming.blockList
        copy.mapLocal = incoming.mapLocal; copy.mapRemote = incoming.mapRemote
        copy.breakpoints = incoming.breakpoints; copy.scripting = incoming.scripting
        copy.dnsSpoofing = incoming.dnsSpoofing; copy.reverseProxy = incoming.reverseProxy
        return copy
    }
}
