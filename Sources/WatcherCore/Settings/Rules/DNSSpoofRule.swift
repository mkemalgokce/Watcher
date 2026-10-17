import Foundation

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
