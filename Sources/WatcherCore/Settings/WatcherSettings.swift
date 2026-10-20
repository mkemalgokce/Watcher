import Foundation

/// Everything configurable, persisted as one JSON document shared by the app and the CLI.
public struct WatcherSettings: Codable, Equatable, Sendable {
    public var port = 9090
    /// Listen on every interface (so phones and simulators can connect) instead of only localhost.
    public var listenOnAllInterfaces = false
    /// Fall back to a free port when `port` is taken.
    public var autoSelectPort = true
    public var socks = SocksSettings()
    public var sslProxying = SSLProxyingSettings()
    public var noCaching = false
    public var allowList = RuleSet<AllowRule>()
    public var blockList = RuleSet<BlockRule>()
    public var mapLocal = RuleSet<MapLocalRule>()
    public var mapRemote = RuleSet<MapRemoteRule>()
    public var breakpoints = RuleSet<BreakpointRule>()
    public var scripting = RuleSet<ScriptRule>()
    public var throttle = ThrottleSettings()
    public var dnsSpoofing = RuleSet<DNSSpoofRule>()
    public var reverseProxy = RuleSet<ReverseProxyRule>()
    public var externalProxy = ExternalProxySettings()
    /// `.desc` files (descriptor sets) and the rules that pick a message type per URL.
    public var protobufSchemas: [String] = []
    public var protobuf = RuleSet<ProtobufRule>()
    public var customCertificates = RuleSet<CustomCertificateRule>()
    /// Offer HTTP/2 to clients on decrypted connections (otherwise HTTP/1.1 only).
    public var preferHTTP2 = true
    /// With "listen on all interfaces", also accept IPv6 (binds `::`, which covers IPv4 too).
    public var listenOnIPv6 = false
    /// A client that refuses Watcher's certificate (certificate pinning) gets its host added to the never-decrypt list.
    public var autoIgnoreSSLPinning = false
    public var accessControl = AccessControlSettings()
    /// File that receives TLS session secrets in NSS key-log format, for Wireshark. Empty switches it off. The file is sensitive.
    public var tlsKeyLogFile = ""
    /// Validity of generated per-host certificates, 1 to 825 days (Apple rejects longer ones).
    public var leafCertificateValidityDays = 365
    /// Oldest requests are dropped beyond this many; 0 keeps everything. Bounded by default so a recording left running
    /// for days neither grows without end nor slows the window down.
    public static let defaultMaxFlows = 10000
    public var maxFlows = WatcherSettings.defaultMaxFlows
    /// Adds an `X-Watcher-Applied` response header naming the tools that touched a request.
    public var markModifiedTraffic = false
    /// Hides Authorization, Cookie and similar header values from MCP output.
    public var mcpRedaction = true
    public var hideAppleTraffic = false
    /// Hides requests sent by macOS daemons and system agents.
    public var hideSystemServices = false
    public var includeProxyInCURL = false
    /// Repeating a request strips cache validators so the server answers afresh.
    public var noCachingOnRepeat = false
    public var composeTimeoutSeconds = 60
    /// The app points the macOS system proxy at Watcher while it runs and restores it afterwards.
    public var autoSystemProxy = false
    /// User-written viewers: JavaScript that turns a matching message into text, shown as an extra tab.
    public var previewers = RuleSet<PreviewerRule>()
    /// Response templates offered when a breakpoint holds a response, next to the built-in ones.
    public var breakpointTemplates: [BreakpointTemplate] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case port, listenOnAllInterfaces, autoSelectPort, socks, sslProxying, noCaching, allowList, blockList
        case mapLocal, mapRemote, breakpoints, scripting, throttle, dnsSpoofing, reverseProxy, externalProxy, protobufSchemas, protobuf
        case customCertificates, breakpointTemplates, previewers
        case preferHTTP2, listenOnIPv6, autoIgnoreSSLPinning, accessControl, tlsKeyLogFile, leafCertificateValidityDays, maxFlows
        case markModifiedTraffic, mcpRedaction, hideAppleTraffic, hideSystemServices
        case includeProxyInCURL, noCachingOnRepeat
        case composeTimeoutSeconds, autoSystemProxy
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        port = try c.decode(.port, default: port)
        listenOnAllInterfaces = try c.decode(.listenOnAllInterfaces, default: listenOnAllInterfaces)
        autoSelectPort = try c.decode(.autoSelectPort, default: autoSelectPort)
        socks = try c.decode(.socks, default: socks)
        sslProxying = try c.decode(.sslProxying, default: sslProxying)
        noCaching = try c.decode(.noCaching, default: noCaching)
        allowList = try c.decode(.allowList, default: allowList)
        blockList = try c.decode(.blockList, default: blockList)
        mapLocal = try c.decode(.mapLocal, default: mapLocal)
        mapRemote = try c.decode(.mapRemote, default: mapRemote)
        breakpoints = try c.decode(.breakpoints, default: breakpoints)
        scripting = try c.decode(.scripting, default: scripting)
        throttle = try c.decode(.throttle, default: throttle)
        dnsSpoofing = try c.decode(.dnsSpoofing, default: dnsSpoofing)
        reverseProxy = try c.decode(.reverseProxy, default: reverseProxy)
        externalProxy = try c.decode(.externalProxy, default: externalProxy)
        protobufSchemas = try c.decode(.protobufSchemas, default: protobufSchemas)
        protobuf = try c.decode(.protobuf, default: protobuf)
        customCertificates = try c.decode(.customCertificates, default: customCertificates)
        breakpointTemplates = try c.decode(.breakpointTemplates, default: breakpointTemplates)
        previewers = try c.decode(.previewers, default: previewers)
        preferHTTP2 = try c.decode(.preferHTTP2, default: preferHTTP2)
        listenOnIPv6 = try c.decode(.listenOnIPv6, default: listenOnIPv6)
        autoIgnoreSSLPinning = try c.decode(.autoIgnoreSSLPinning, default: autoIgnoreSSLPinning)
        accessControl = try c.decode(.accessControl, default: accessControl)
        tlsKeyLogFile = try c.decode(.tlsKeyLogFile, default: tlsKeyLogFile)
        leafCertificateValidityDays = try c.decode(.leafCertificateValidityDays, default: leafCertificateValidityDays)
        maxFlows = try c.decode(.maxFlows, default: maxFlows)
        markModifiedTraffic = try c.decode(.markModifiedTraffic, default: markModifiedTraffic)
        mcpRedaction = try c.decode(.mcpRedaction, default: mcpRedaction)
        hideAppleTraffic = try c.decode(.hideAppleTraffic, default: hideAppleTraffic)
        hideSystemServices = try c.decode(.hideSystemServices, default: hideSystemServices)
        includeProxyInCURL = try c.decode(.includeProxyInCURL, default: includeProxyInCURL)
        noCachingOnRepeat = try c.decode(.noCachingOnRepeat, default: noCachingOnRepeat)
        composeTimeoutSeconds = try c.decode(.composeTimeoutSeconds, default: composeTimeoutSeconds)
        autoSystemProxy = try c.decode(.autoSystemProxy, default: autoSystemProxy)
    }
}
