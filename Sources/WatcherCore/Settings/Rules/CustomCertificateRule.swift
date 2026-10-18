/// Certificates supplied by the user as PKCS#12 files: a server identity Watcher presents for a host
/// (instead of a generated one) or a client identity it presents to an upstream that demands mutual TLS.
public struct CustomCertificateRule: ToolRule {
    public enum Role: String, Codable, Sendable { case server, client }

    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    /// Host pattern (`*.example.com`).
    public var host: String
    public var role: Role
    public var p12Path: String
    public var passphrase: String

    public init(name: String = "", isEnabled: Bool = true, host: String, role: Role, p12Path: String, passphrase: String = "") {
        self.name = name; self.isEnabled = isEnabled; self.host = host; self.role = role; self.p12Path = p12Path; self.passphrase = passphrase
    }
}
