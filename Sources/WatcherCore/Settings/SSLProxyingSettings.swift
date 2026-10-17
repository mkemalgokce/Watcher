import Foundation

public struct SSLProxyingSettings: Codable, Equatable, Sendable {
    public var include: [String]
    public var exclude: [String]
    public init(include: [String] = ["*"], exclude: [String] = []) {
        self.include = include; self.exclude = exclude
    }
}
