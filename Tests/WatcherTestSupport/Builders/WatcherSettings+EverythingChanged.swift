import Foundation
import WatcherCore

public extension WatcherSettings {
    /// Every setting moved off its default, so a decoder that drops or mislabels one key is caught.
    static var everythingChanged: WatcherSettings {
        var settings = WatcherSettings()
        let match = MatchingRule(pattern: "*")
        settings.port = 1234; settings.listenOnAllInterfaces = true; settings.autoSelectPort = false
        settings.socks = SocksSettings(isEnabled: true, port: 1080)
        settings.noCaching = true
        settings.allowList = RuleSet(isEnabled: true, rules: [AllowRule(name: "a", matching: match)])
        settings.blockList = RuleSet(isEnabled: true, rules: [BlockRule(name: "b", matching: match)])
        settings.mapRemote = RuleSet(
            isEnabled: true,
            rules: [MapRemoteRule(matching: match, destination: .init(host: "h"))]
        )
        settings.throttle = ThrottleSettings(isEnabled: true, profile: NetworkProfile.presets[1], host: "h")
        settings.externalProxy = ExternalProxySettings(isEnabled: true, kind: .socks, host: "p", port: 1)
        settings.protobufSchemas = ["a.desc"]
        settings.preferHTTP2 = false; settings.listenOnIPv6 = true; settings.autoIgnoreSSLPinning = true
        settings.accessControl = AccessControlSettings(isEnabled: true, allowedAddresses: ["10.*"])
        settings.tlsKeyLogFile = "/k"; settings.leafCertificateValidityDays = 30; settings.maxFlows = 5
        settings.markModifiedTraffic = true; settings.mcpRedaction = false; settings.hideAppleTraffic = true
        settings.includeProxyInCURL = true; settings.noCachingOnRepeat = true; settings.composeTimeoutSeconds = 9
        settings.autoSystemProxy = true
        settings.breakpointTemplates = [BreakpointTemplate(name: "t", status: 418)]
        return settings
    }
}
