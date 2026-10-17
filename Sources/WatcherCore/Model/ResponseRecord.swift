import Foundation

public struct ResponseRecord: Codable, Equatable, Sendable {
    public var status: Int
    public var headers: [Header]
    public var body: Data
    public init(status: Int, headers: [Header] = [], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }
}
