import Foundation

/// Where an http(s) URL points: the parts a request needs.
public struct HTTPEndpoint: Equatable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int
    public let target: String

    public init?(_ address: String) {
        guard let components = URLComponents(string: address), let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme)
        else { return nil }
        self.scheme = scheme
        self.host = host
        port = components.port ?? RequestRecord.defaultPort(for: scheme)
        target = components.originForm
    }
}
