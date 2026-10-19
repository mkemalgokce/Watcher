import Foundation

public extension URLComponents {
    /// The request target of an absolute URL: its percent-encoded path (at least `/`) and query.
    var originForm: String {
        (percentEncodedPath.isEmpty ? "/" : percentEncodedPath) + (percentEncodedQuery.map { "?\($0)" } ?? "")
    }
}
