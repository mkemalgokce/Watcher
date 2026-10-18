import Foundation

/// A fresh directory under the system temporary folder, removed with everything in it when this object goes away.
public final class TemporaryDirectory {
    public let url: URL

    public init(prefix: String = "watcher-test") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func appending(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
