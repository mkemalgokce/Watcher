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
        settings.sslProxying = SSLProxyingSettings(include: ["*.a"], exclude: ["b"])
        settings.mapLocal = RuleSet(isEnabled: true, rules: [MapLocalRule(matching: match, source: .directory("/d"))])
        settings.breakpoints = RuleSet(isEnabled: true, rules: [BreakpointRule(matching: match)])
        settings.scripting = RuleSet(isEnabled: true, rules: [ScriptRule(matching: match, source: "s")])
        settings.dnsSpoofing = RuleSet(isEnabled: true, rules: [DNSSpoofRule(host: "h", address: "1.2.3.4")])
        settings.reverseProxy = RuleSet(isEnabled: true, rules: [ReverseProxyRule(localPort: 1, remoteHost: "r")])
        settings.protobuf = RuleSet(isEnabled: true, rules: [ProtobufRule(matching: match, requestType: "R")])
        settings.customCertificates = RuleSet(
            isEnabled: true,
            rules: [CustomCertificateRule(host: "h", role: .client, p12Path: "/c.p12")]
        )
        settings.previewers = RuleSet(isEnabled: true, rules: [PreviewerRule(matching: match, source: "p")])
        return settings
    }
}
