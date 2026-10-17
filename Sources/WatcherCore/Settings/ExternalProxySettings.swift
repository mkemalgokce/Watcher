import Foundation

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
