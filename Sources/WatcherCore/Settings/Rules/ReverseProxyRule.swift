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
