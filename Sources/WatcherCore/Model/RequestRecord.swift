import Foundation

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
    /// The raw process behind `clientApp`, which names its owner; nil in records saved before kinds existed.
    public var clientProcess: String?
    public var clientKind: ClientKind?
    /// Outermost `.app` folder of the sending program, for its icon.
    public var clientBundlePath: String?

    public var url: String {
        "\(scheme)://\(host.contains(":") ? "[\(host)]" : host)\(usesDefaultPort ? "" : ":\(port)")\(path)"
    }

    /// What clients assume when a URL names no port.
    public static func defaultPort(for scheme: String) -> Int {
        ["https", "wss"].contains(scheme) ? 443 : 80
    }

    /// The path up to the query; the root when nothing is left.
    public var pathWithoutQuery: String {
        Self.pathWithoutQuery(of: path)
    }

    public static func pathWithoutQuery(of path: String) -> String {
        let bare = path.prefix { $0 != "?" }
        return bare.isEmpty ? "/" : String(bare)
    }

    public var usesDefaultPort: Bool {
        ["http", "https"].contains(scheme) && port == Self.defaultPort(for: scheme)
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

public extension RequestRecord {
    mutating func attribute(to client: ClientIdentity) {
        clientApp = client.app; clientProcess = client.process
        clientKind = client.kind; clientBundlePath = client.bundlePath
    }

    /// The request without cache validators and with no-cache headers, so the server answers afresh.
    func droppingCacheValidators() -> RequestRecord {
        var copy = self
        copy.headers.removeAll { ["if-none-match", "if-modified-since"].contains($0.name.lowercased()) }
        copy.headers.set("Cache-Control", "no-cache, no-store")
        copy.headers.set("Pragma", "no-cache")
        return copy
    }
}
