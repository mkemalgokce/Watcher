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

/// Keeps the directory alive for the whole body, even when the body only touches URLs derived from it.
public func withTemporaryDirectory<R>(
    prefix: String = "watcher-test",
    _ body: (TemporaryDirectory) throws -> R
) throws -> R {
    let directory = try TemporaryDirectory(prefix: prefix)
    return try withExtendedLifetime(directory) { try body(directory) }
}

public func withTemporaryDirectory<R>(
    prefix: String = "watcher-test",
    _ body: (TemporaryDirectory) async throws -> R
) async throws -> R {
    let directory = try TemporaryDirectory(prefix: prefix)
    defer { withExtendedLifetime(directory) {} }
    return try await body(directory)
}
