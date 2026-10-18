import WatcherCore

/// The rule a tool's add button creates, valid as it stands so a new rule never starts out flagged.
enum NewRule {
    private static let everything = MatchingRule(pattern: "*")

    static func block() -> BlockRule {
        BlockRule(matching: everything)
    }

    static func allow() -> AllowRule {
        AllowRule(matching: everything)
    }

    static func mapLocal() -> MapLocalRule {
        MapLocalRule(matching: everything, source: .file(""))
    }

    static func mapRemote() -> MapRemoteRule {
        MapRemoteRule(matching: everything, destination: .init())
    }

    static func breakpoint() -> BreakpointRule {
        BreakpointRule(matching: everything)
    }

    static func scripting() -> ScriptRule {
        ScriptRule(matching: everything)
    }

    static func previewer() -> PreviewerRule {
        PreviewerRule(matching: everything)
    }

    static func protobuf() -> ProtobufRule {
        ProtobufRule(matching: everything)
    }

    static func dns() -> DNSSpoofRule {
        DNSSpoofRule(host: "example.com", address: "127.0.0.1")
    }

    static func reverseProxy() -> ReverseProxyRule {
        ReverseProxyRule(localPort: 9191, remoteHost: "example.com")
    }

    static func certificate() -> CustomCertificateRule {
        CustomCertificateRule(host: "api.example.com", role: .server, p12Path: "")
    }
}
