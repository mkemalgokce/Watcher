import Foundation

/// Files of this package's checkout, for tests that check the sources themselves.
public enum SourceTree {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Environment
        .deletingLastPathComponent() // WatcherTestSupport
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent()

    /// `path` is relative to the package root, such as `Sources/WatcherUI`.
    public static func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    public static func text(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }
}
