import Foundation

public struct MapRemoteRule: ToolRule {
    /// `nil` parts keep the original request's value.
    public struct Destination: Codable, Equatable, Sendable {
        public var scheme: String?
        public var host: String?
        public var port: Int?
        public var path: String?
        public var query: String?

        public init(scheme: String? = nil, host: String? = nil, port: Int? = nil, path: String? = nil, query: String? = nil) {
            self.scheme = scheme; self.host = host; self.port = port; self.path = path; self.query = query
        }
    }

    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    public var destination: Destination
    /// Keep the client's original `Host` header instead of naming the new host.
    public var preserveHostHeader: Bool

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, destination: Destination, preserveHostHeader: Bool = false) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.destination = destination; self.preserveHostHeader = preserveHostHeader
    }

    private enum CodingKeys: String, CodingKey { case name, isEnabled, matching, destination, preserveHostHeader, folder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            matching: c.decode(MatchingRule.self, forKey: .matching),
            destination: c.decode(Destination.self, forKey: .destination)
        )
        name = try c.decode(.name, default: name)
        isEnabled = try c.decode(.isEnabled, default: isEnabled)
        preserveHostHeader = try c.decode(.preserveHostHeader, default: preserveHostHeader)
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
    }
}
