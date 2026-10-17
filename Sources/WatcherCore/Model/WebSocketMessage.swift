import Foundation

public struct WebSocketMessage: Codable, Equatable, Sendable {
    public enum Direction: String, Codable, Sendable { case clientToServer, serverToClient }
    public enum Kind: String, Codable, Sendable { case text, binary, close, ping, pong }

    public var direction: Direction
    public var kind: Kind
    public var payload: Data
    public var date: Date
    /// True for permessage-deflate frames, whose payload is shown still compressed.
    public var isCompressed: Bool

    public init(direction: Direction, kind: Kind, payload: Data, date: Date = Date(), isCompressed: Bool = false) {
        self.direction = direction; self.kind = kind; self.payload = payload; self.date = date; self.isCompressed = isCompressed
    }
}
