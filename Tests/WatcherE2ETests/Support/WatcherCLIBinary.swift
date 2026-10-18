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

    /// The environment of a launched `watcher-cli`: its own home, and its coverage data kept out of the repository.
    static func environment(home: URL) -> [String: String] {
        ProcessInfo.processInfo.environment.merging([
            "WATCHER_HOME": home.path,
            "LLVM_PROFILE_FILE": home.appendingPathComponent("watcher-cli-%p.profraw").path,
        ]) { $1 }
    }
}
