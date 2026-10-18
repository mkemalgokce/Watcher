import Foundation

/// The debugging tools that can be switched on and off, with the name each is known by outside the app.
public enum ToolKind: String, CaseIterable, Sendable {
    case blockList = "block-list"
    case allowList = "allow-list"
    case mapLocal = "map-local"
    case mapRemote = "map-remote"
    case breakpoint
    case scripting
    case dnsSpoofing = "dns-spoofing"
    case reverseProxy = "reverse-proxy"
    case networkCondition = "network-condition"
    case noCaching = "no-caching"
    case externalProxy = "external-proxy"

    /// The setting that switches the tool on or off.
    public var switchPath: WritableKeyPath<WatcherSettings, Bool> {
        switch self {
        case .blockList: \.blockList.isEnabled
        case .allowList: \.allowList.isEnabled
        case .mapLocal: \.mapLocal.isEnabled
        case .mapRemote: \.mapRemote.isEnabled
        case .breakpoint: \.breakpoints.isEnabled
        case .scripting: \.scripting.isEnabled
        case .dnsSpoofing: \.dnsSpoofing.isEnabled
        case .reverseProxy: \.reverseProxy.isEnabled
        case .networkCondition: \.throttle.isEnabled
        case .noCaching: \.noCaching
        case .externalProxy: \.externalProxy.isEnabled
        }
    }

    /// `on, 2 rule(s)` for a tool with rules, else just its state.
    public func summary(in settings: WatcherSettings) -> String {
        let state = settings[keyPath: switchPath] ? "on" : "off"
        switch self {
        case .blockList: return Self.rules(settings.blockList)
        case .allowList: return Self.rules(settings.allowList)
        case .mapLocal: return Self.rules(settings.mapLocal)
        case .mapRemote: return Self.rules(settings.mapRemote)
        case .breakpoint: return Self.rules(settings.breakpoints)
        case .scripting: return Self.rules(settings.scripting)
        case .dnsSpoofing: return Self.rules(settings.dnsSpoofing)
        case .reverseProxy: return Self.rules(settings.reverseProxy)
        case .networkCondition: return settings.throttle.isEnabled ? "on (\(settings.throttle.profile.name))" : state
        case .noCaching, .externalProxy: return state
        }
    }

    private static func rules(_ set: RuleSet<some ToolRule>) -> String {
        "\(set.isEnabled ? "on" : "off"), \(set.rules.count) rule(s)"
    }
}
