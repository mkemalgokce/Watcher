import Foundation

/// The body of a site's icon, or nil when it cannot be fetched.
typealias FaviconDownload = @Sendable (URL) async -> Data?

enum LiveFaviconDownload {
    /// Straight to the site: an empty proxy dictionary keeps this out of the system proxy, i.e. out of Watcher's own list.
    static func fetch(_ url: URL) async -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
