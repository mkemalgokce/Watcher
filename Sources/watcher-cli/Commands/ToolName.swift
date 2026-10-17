import ArgumentParser
import Foundation
import WatcherCore

/// Tools a running (or later started) Watcher picks up from the shared settings file.
enum ToolName: String, CaseIterable, ExpressibleByArgument {
    case breakpoint, mapLocal = "map-local", mapRemote = "map-remote", scripting
    case blockList = "block-list", allowList = "allow-list", reverseProxy = "reverse-proxy"
    case networkCondition = "network-condition", noCaching = "no-caching"
    case dnsSpoofing = "dns-spoofing", externalProxy = "external-proxy"

    func set(_ enabled: Bool, in settings: inout WatcherSettings) {
        switch self {
        case .breakpoint: settings.breakpoints.isEnabled = enabled
        case .mapLocal: settings.mapLocal.isEnabled = enabled
        case .mapRemote: settings.mapRemote.isEnabled = enabled
        case .scripting: settings.scripting.isEnabled = enabled
        case .blockList: settings.blockList.isEnabled = enabled
        case .allowList: settings.allowList.isEnabled = enabled
        case .reverseProxy: settings.reverseProxy.isEnabled = enabled
        case .networkCondition: settings.throttle.isEnabled = enabled
        case .noCaching: settings.noCaching = enabled
        case .dnsSpoofing: settings.dnsSpoofing.isEnabled = enabled
        case .externalProxy: settings.externalProxy.isEnabled = enabled
        }
    }
}
