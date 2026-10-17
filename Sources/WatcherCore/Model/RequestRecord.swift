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
