import Foundation

public protocol ToolRule: Codable, Equatable, Sendable {
    var isEnabled: Bool { get set }
    /// Optional folder the rule is filed under; rules of one folder can be switched on or off together.
    var folder: String? { get set }
}

/// A tool's master switch plus its rules.
public struct RuleSet<Rule: ToolRule>: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var rules: [Rule]

    public init(isEnabled: Bool = false, rules: [Rule] = []) {
        self.isEnabled = isEnabled; self.rules = rules
    }

    /// Rules that should currently take effect.
    public var active: [Rule] {
        isEnabled ? rules.filter(\.isEnabled) : []
    }

    /// Folder names in the order they first appear.
    public var folders: [String] {
        var seen: [String] = []
        for case let name? in rules.map(\.folder) where !seen.contains(name) {
            seen.append(name)
        }
        return seen
    }

    /// Switches every rule filed under `name` on or off.
    public mutating func setFolder(_ name: String, enabled: Bool) {
        for index in rules.indices where rules[index].folder == name {
            rules[index].isEnabled = enabled
        }
    }
}

public struct BlockRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    /// When true the blocked request does not appear in the session list.
    public var hidesRequest: Bool

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, hidesRequest: Bool = false) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.hidesRequest = hidesRequest
    }
}

public struct AllowRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching
    }
}

public struct MapLocalRule: ToolRule {
    public enum Source: Codable, Equatable, Sendable {
        case file(String)
        /// Serves `<directory>/<request path after the pattern's static prefix>`.
        case directory(String)
    }

    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    public var source: Source
    public var delayMilliseconds: Int

    public init(
        name: String = "",
        isEnabled: Bool = true,
        matching: MatchingRule,
        source: Source,
        delayMilliseconds: Int = 0
    ) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching
        self.source = source; self.delayMilliseconds = delayMilliseconds
    }
}

public struct MapRemoteRule: ToolRule {
    /// `nil` parts keep the original request's value.
    public struct Destination: Codable, Equatable, Sendable {
        public var scheme: String?
        public var host: String?
        public var port: Int?
        public var path: String?
        public var query: String?

        public init(scheme: String? = nil, host: String? = nil, port: Int? = nil, path: String? = nil, query: String? = nil) {
            self.scheme = scheme; self.host = host; self.port = port; self.path = path; self.query = query
        }
    }

    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    public var destination: Destination
    /// Keep the client's original `Host` header instead of naming the new host.
    public var preserveHostHeader: Bool

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, destination: Destination, preserveHostHeader: Bool = false) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.destination = destination; self.preserveHostHeader = preserveHostHeader
    }

    private enum CodingKeys: String, CodingKey { case name, isEnabled, matching, destination, preserveHostHeader, folder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: c.decode(.name, default: ""),
            isEnabled: c.decode(.isEnabled, default: true),
            matching: c.decode(MatchingRule.self, forKey: .matching),
            destination: c.decode(Destination.self, forKey: .destination),
            preserveHostHeader: c.decode(.preserveHostHeader, default: false)
        )
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
    }
}

public struct BreakpointRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    public var onRequest: Bool
    public var onResponse: Bool

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, onRequest: Bool = true, onResponse: Bool = true) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching
        self.onRequest = onRequest; self.onResponse = onResponse
    }
}

public struct ScriptRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    /// JavaScript defining `onRequest(context, url, request)` and/or `onResponse(context, url, request, response)`.
    public var source: String

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, source: String = ScriptRule.template) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.source = source
    }

    public static let template = """
    async function onRequest(context, url, request) {
      // request.headers["X-Watcher"] = "1";
      // request.queries["debug"] = "true";
      return request;
    }

    async function onResponse(context, url, request, response) {
      // response.statusCode = 500;
      // response.headers["Content-Type"] = "application/json";
      // response.bodyFilePath = "~/Desktop/mock.json";
      return response;
    }
    """
}

public struct NetworkProfile: Codable, Equatable, Sendable {
    public var name: String
    /// 0 means unlimited.
    public var downloadKbps: Int
    public var uploadKbps: Int
    public var latencyMilliseconds: Int
    public var packetLossPercent: Int

    public init(name: String, downloadKbps: Int = 0, uploadKbps: Int = 0, latencyMilliseconds: Int = 0, packetLossPercent: Int = 0) {
        self.name = name; self.downloadKbps = downloadKbps; self.uploadKbps = uploadKbps
        self.latencyMilliseconds = latencyMilliseconds; self.packetLossPercent = packetLossPercent
    }

    public static let presets: [NetworkProfile] = [
        .init(name: "3G", downloadKbps: 780, uploadKbps: 330, latencyMilliseconds: 100),
        .init(name: "Edge", downloadKbps: 240, uploadKbps: 200, latencyMilliseconds: 400),
        .init(name: "LTE", downloadKbps: 12000, uploadKbps: 5000, latencyMilliseconds: 50),
        .init(name: "Wi-Fi", downloadKbps: 40000, uploadKbps: 33000, latencyMilliseconds: 1),
        .init(name: "very_bad_network", downloadKbps: 100, uploadKbps: 50, latencyMilliseconds: 800, packetLossPercent: 10),
        .init(name: "100_percent_loss", packetLossPercent: 100),
    ]
}

public struct ThrottleSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var profile: NetworkProfile
    /// `host` or `host:port`; no wildcards. Empty applies to all traffic.
    public var host: String
    /// Profiles the user saved under their own name; offered next to the built-in presets.
    public var customProfiles: [NetworkProfile]

    public init(isEnabled: Bool = false, profile: NetworkProfile = NetworkProfile.presets[0], host: String = "", customProfiles: [NetworkProfile] = []) {
        self.isEnabled = isEnabled; self.profile = profile; self.host = host; self.customProfiles = customProfiles
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, profile, host, customProfiles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            isEnabled: c.decode(.isEnabled, default: false),
            profile: c.decode(.profile, default: NetworkProfile.presets[0]),
            host: c.decode(.host, default: ""),
            customProfiles: c.decode(.customProfiles, default: [])
        )
    }

    /// Built-in presets followed by the saved ones.
    public var availableProfiles: [NetworkProfile] {
        NetworkProfile.presets + customProfiles
    }

    /// Saves `profile` under its name, replacing a saved profile with the same name; presets cannot be overwritten.
    public mutating func saveCurrentProfile() {
        guard !profile.name.isEmpty, !NetworkProfile.presets.contains(where: { $0.name == profile.name }) else { return }
        if let index = customProfiles.firstIndex(where: { $0.name == profile.name }) {
            customProfiles[index] = profile
        } else {
            customProfiles.append(profile)
        }
    }

    public mutating func deleteCustomProfile(named name: String) {
        customProfiles.removeAll { $0.name == name }
    }
}

public struct DNSSpoofRule: ToolRule {
    public var isEnabled: Bool
    public var folder: String?
    /// Exact host name (no wildcard); the connection goes to `address` instead.
    public var host: String
    public var address: String

    public init(isEnabled: Bool = true, host: String, address: String) {
        self.isEnabled = isEnabled; self.host = host; self.address = address
    }
}

public struct ReverseProxyRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
    public var forceTLS: Bool
    public var preserveHost: Bool

    public init(
        name: String = "",
        isEnabled: Bool = true,
        localPort: Int,
        remoteHost: String,
        remotePort: Int = 443,
        forceTLS: Bool = false,
        preserveHost: Bool = false
    ) {
        self.name = name; self.isEnabled = isEnabled; self.localPort = localPort; self.remoteHost = remoteHost
        self.remotePort = remotePort; self.forceTLS = forceTLS; self.preserveHost = preserveHost
    }

    var usesTLS: Bool {
        forceTLS || remotePort == 443
    }
}

public struct ExternalProxySettings: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case http, socks, pac }

    public var isEnabled: Bool
    public var kind: Kind
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    /// Location of the proxy auto-config script when `kind` is `.pac`.
    public var pacURL: String
    /// Hosts that skip the external proxy; `localhost` and `127.0.0.1` always do.
    public var bypass: [String]

    public init(
        isEnabled: Bool = false,
        kind: Kind = .http,
        host: String = "127.0.0.1",
        port: Int = 8080,
        username: String = "",
        password: String = "",
        pacURL: String = "",
        bypass: [String] = []
    ) {
        self.isEnabled = isEnabled; self.kind = kind; self.host = host; self.port = port
        self.username = username; self.password = password; self.pacURL = pacURL; self.bypass = bypass
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, kind, host, port, username, password, pacURL, bypass }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            isEnabled: c.decode(.isEnabled, default: false),
            kind: c.decode(.kind, default: .http),
            host: c.decode(.host, default: "127.0.0.1"),
            port: c.decode(.port, default: 8080),
            username: c.decode(.username, default: ""),
            password: c.decode(.password, default: ""),
            pacURL: c.decode(.pacURL, default: ""),
            bypass: c.decode(.bypass, default: [])
        )
    }
}

public struct SSLProxyingSettings: Codable, Equatable, Sendable {
    public var include: [String]
    public var exclude: [String]
    public init(include: [String] = ["*"], exclude: [String] = []) {
        self.include = include; self.exclude = exclude
    }
}

/// Which LAN clients may use the proxy. Loopback is always allowed; with the switch on, other addresses must match a pattern (`192.168.1.*`).
public struct AccessControlSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var allowedAddresses: [String]
    public init(isEnabled: Bool = false, allowedAddresses: [String] = []) {
        self.isEnabled = isEnabled; self.allowedAddresses = allowedAddresses
    }

    public func allows(_ address: String?) -> Bool {
        guard let address else { return false }
        if address == "127.0.0.1" || address == "::1" {
            return true
        }
        return !isEnabled || HostList(allowedAddresses).matches(address)
    }
}

public struct SocksSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var port: Int
    public init(isEnabled: Bool = false, port: Int = 8889) {
        self.isEnabled = isEnabled; self.port = port
    }
}

extension KeyedDecodingContainer {
    /// Missing keys fall back to `value`, so settings files written by older versions keep loading.
    func decode<T: Decodable>(_ key: Key, default value: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? value
    }
}

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
    /// Oldest requests are dropped beyond this many; 0 keeps everything.
    public var maxFlows = 0
    /// Adds an `X-Watcher-Applied` response header naming the tools that touched a request.
    public var markModifiedTraffic = false
    /// Hides Authorization, Cookie and similar header values from MCP output.
    public var mcpRedaction = true
    public var hideAppleTraffic = false
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
        case markModifiedTraffic, mcpRedaction, hideAppleTraffic, includeProxyInCURL, noCachingOnRepeat, composeTimeoutSeconds, autoSystemProxy
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        port = try c.decode(.port, default: port); listenOnAllInterfaces = try c.decode(.listenOnAllInterfaces, default: false)
        autoSelectPort = try c.decode(.autoSelectPort, default: true); socks = try c.decode(.socks, default: socks)
        sslProxying = try c.decode(.sslProxying, default: sslProxying); noCaching = try c.decode(.noCaching, default: false)
        allowList = try c.decode(.allowList, default: allowList); blockList = try c.decode(.blockList, default: blockList)
        mapLocal = try c.decode(.mapLocal, default: mapLocal); mapRemote = try c.decode(.mapRemote, default: mapRemote)
        breakpoints = try c.decode(.breakpoints, default: breakpoints); scripting = try c.decode(.scripting, default: scripting)
        throttle = try c.decode(.throttle, default: throttle); dnsSpoofing = try c.decode(.dnsSpoofing, default: dnsSpoofing)
        reverseProxy = try c.decode(.reverseProxy, default: reverseProxy); externalProxy = try c.decode(.externalProxy, default: externalProxy)
        protobufSchemas = try c.decode(.protobufSchemas, default: []); protobuf = try c.decode(.protobuf, default: protobuf)
        customCertificates = try c.decode(.customCertificates, default: customCertificates)
        breakpointTemplates = try c.decode(.breakpointTemplates, default: [])
        previewers = try c.decode(.previewers, default: previewers)
        preferHTTP2 = try c.decode(.preferHTTP2, default: true); listenOnIPv6 = try c.decode(.listenOnIPv6, default: false)
        autoIgnoreSSLPinning = try c.decode(.autoIgnoreSSLPinning, default: false); accessControl = try c.decode(.accessControl, default: accessControl)
        tlsKeyLogFile = try c.decode(.tlsKeyLogFile, default: ""); leafCertificateValidityDays = try c.decode(.leafCertificateValidityDays, default: 365)
        maxFlows = try c.decode(.maxFlows, default: 0); markModifiedTraffic = try c.decode(.markModifiedTraffic, default: false)
        mcpRedaction = try c.decode(.mcpRedaction, default: true); hideAppleTraffic = try c.decode(.hideAppleTraffic, default: false)
        includeProxyInCURL = try c.decode(.includeProxyInCURL, default: false); noCachingOnRepeat = try c.decode(.noCachingOnRepeat, default: false)
        composeTimeoutSeconds = try c.decode(.composeTimeoutSeconds, default: 60); autoSystemProxy = try c.decode(.autoSystemProxy, default: false)
    }
}

/// A canned response a held breakpoint can be turned into with one click.
public struct BreakpointTemplate: Codable, Equatable, Sendable {
    public var name: String
    public var status: Int
    public var headers: [Header]
    public var body: String

    public init(name: String, status: Int, headers: [Header] = [], body: String = "") {
        self.name = name; self.status = status; self.headers = headers; self.body = body
    }

    private static func error(_ status: Int, _ name: String, _ code: String, extra: [Header] = []) -> BreakpointTemplate {
        BreakpointTemplate(name: "\(status) \(name)", status: status, headers: [Header("Content-Type", "application/json")] + extra, body: #"{"error":"\#(code)"}"#)
    }

    public static let builtIn = [
        error(401, "Unauthorized", "unauthorized"), error(404, "Not Found", "not_found"), error(429, "Too Many Requests", "too_many_requests", extra: [Header("Retry-After", "60")]),
        error(500, "Internal Server Error", "internal_error"), error(503, "Service Unavailable", "service_unavailable", extra: [Header("Retry-After", "30")]),
    ]
}

public extension WatcherSettings {
    var allBreakpointTemplates: [BreakpointTemplate] {
        BreakpointTemplate.builtIn + breakpointTemplates
    }
}

public struct PreviewerRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    /// JavaScript defining `preview(message)`; `message` has `url`, `status`, `headers`, `body` (text or null) and `bodyBase64`.
    public var source: String

    public init(name: String = "Previewer", isEnabled: Bool = true, matching: MatchingRule, source: String = PreviewerRule.template) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.source = source
    }

    public static let template = """
    function preview(message) {
      // Return a string, or any JSON value to have it pretty-printed.
      return atob(message.bodyBase64);
    }
    """
}
