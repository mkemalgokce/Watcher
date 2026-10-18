import Foundation

/// Where the app keeps the files it hands to the user: the root certificate, the mocks it creates and the site icons it caches.
public struct SupportPaths: Sendable {
    var directory: URL
    var certificateURL: URL
    var mocksDirectory: URL
    var faviconsDirectory: URL

    init(directory: URL) {
        self.directory = directory
        certificateURL = directory.appendingPathComponent("watcher-ca.pem")
        mocksDirectory = directory.appendingPathComponent("mocks", isDirectory: true)
        faviconsDirectory = directory.appendingPathComponent("favicons", isDirectory: true)
    }
}
