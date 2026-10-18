import Foundation

/// Where the app keeps the files it hands to the user: the root certificate and the mocks it creates.
public struct SupportPaths: Sendable {
    var certificateURL: URL
    var mocksDirectory: URL

    init(directory: URL) {
        certificateURL = directory.appendingPathComponent("watcher-ca.pem")
        mocksDirectory = directory.appendingPathComponent("mocks", isDirectory: true)
    }
}
