import Foundation
import WatcherTestSupport

/// The `watcher-cli` these tests launch: `WATCHER_CLI` when set (`make test-e2e` passes the one `swift build` made),
/// otherwise the one built beside the test bundle. Building it from inside `swift test` would wait forever on the build lock.
enum WatcherCLIBinary {
    static func locate() throws -> URL {
        let binary = ProcessInfo.processInfo.environment["WATCHER_CLI"].map(URL.init(fileURLWithPath:))
            ?? Bundle(for: WatcherCLIProcess.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("watcher-cli")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw TestSupportError("no watcher-cli at \(binary.path); run swift build --product watcher-cli first")
        }
        return binary
    }
}
