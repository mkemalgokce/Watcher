import Foundation

public struct Header: Hashable, Codable, Sendable {
    public var name: String
    public var value: String
    public init(_ name: String, _ value: String) {
        self.name = name; self.value = value
    }
}

public struct RequestRecord: Codable, Equatable, Sendable {
    public var method: String
    public var scheme: String
    public var host: String
    public var port: Int
    public var path: String
    public var headers: [Header]
    public var body: Data
    /// Program on this Mac that sent the request, when it could be determined.
    public var clientApp: String?

    public var url: String {
        let isDefault = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        return "\(scheme)://\(host)\(isDefault ? "" : ":\(port)")\(path)"
    }

    public init(
        method: String,
        scheme: String,
        host: String,
        port: Int,
        path: String,
        headers: [Header] = [],
        body: Data = Data(),
        clientApp: String? = nil
    ) {
        self.method = method; self.scheme = scheme; self.host = host
        self.port = port; self.path = path; self.headers = headers; self.body = body; self.clientApp = clientApp
    }
}

public struct ResponseRecord: Codable, Equatable, Sendable {
    public var status: Int
    public var headers: [Header]
    public var body: Data
    public init(status: Int, headers: [Header] = [], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }
}

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

public struct Flow: Identifiable, Codable, Sendable {
    public enum State: String, Codable, Sendable { case pending, completed, failed, blocked }

    public let id: UUID
    public var sequence: Int
    public var startedAt: Date
    public var duration: TimeInterval?
    public var request: RequestRecord
    public var response: ResponseRecord?
    public var state: State
    public var error: String?
    /// Names of the tools (Map Local, Block List, ...) that touched this flow.
    public var appliedTools: [String]
    public var webSocketMessages: [WebSocketMessage] = []
    /// Seconds from sending the request upstream until its response headers arrived.
    public var timeToFirstByte: TimeInterval?
    /// Protocol spoken to the server, e.g. `HTTP/2`.
    public var upstreamHTTPVersion: String?
    /// What the client negotiated with Watcher on a decrypted connection, e.g. `TLS 1.3 · h2`.
    public var clientTLS: String?
    public var isStarred = false
    public var comment: String?

    public init(sequence: Int, request: RequestRecord) {
        id = UUID(); self.sequence = sequence; startedAt = Date()
        self.request = request; state = .pending; appliedTools = []
    }
}

public extension RequestRecord {
    /// The request without cache validators and with no-cache headers, so the server answers afresh.
    func droppingCacheValidators() -> RequestRecord {
        var copy = self
        copy.headers.removeAll { ["if-none-match", "if-modified-since"].contains($0.name.lowercased()) }
        copy.headers.set("Cache-Control", "no-cache, no-store")
        copy.headers.set("Pragma", "no-cache")
        return copy
    }
}

public extension [Header] {
    func value(for name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    mutating func set(_ name: String, _ value: String) {
        removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        append(Header(name, value))
    }
}

extension Flow {
    private enum CodingKeys: String, CodingKey {
        case id, sequence, startedAt, duration, request, response, state, error, appliedTools, webSocketMessages, timeToFirstByte, upstreamHTTPVersion, clientTLS, isStarred, comment
    }

    /// `webSocketMessages` is optional on disk so sessions saved by older versions still open.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); sequence = try c.decode(Int.self, forKey: .sequence)
        startedAt = try c.decode(Date.self, forKey: .startedAt); duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        request = try c.decode(RequestRecord.self, forKey: .request); response = try c.decodeIfPresent(ResponseRecord.self, forKey: .response)
        state = try c.decode(State.self, forKey: .state); error = try c.decodeIfPresent(String.self, forKey: .error)
        appliedTools = try c.decode([String].self, forKey: .appliedTools)
        webSocketMessages = try c.decode(.webSocketMessages, default: [])
        timeToFirstByte = try c.decodeIfPresent(TimeInterval.self, forKey: .timeToFirstByte)
        upstreamHTTPVersion = try c.decodeIfPresent(String.self, forKey: .upstreamHTTPVersion)
        clientTLS = try c.decodeIfPresent(String.self, forKey: .clientTLS)
        isStarred = try c.decode(.isStarred, default: false)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
    }
}
