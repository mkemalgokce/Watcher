import Foundation

public struct SocksSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var port: Int
    public init(isEnabled: Bool = false, port: Int = 8889) {
        self.isEnabled = isEnabled; self.port = port
    }
}
