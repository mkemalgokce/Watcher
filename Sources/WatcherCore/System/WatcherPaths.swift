import Foundation

public enum WatcherPaths {
    /// `~/.watcher`, or the folder named by `WATCHER_HOME` (for isolated runs and tests; `HOME` itself is not honoured by Foundation).
    public static var supportDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["WATCHER_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".watcher", isDirectory: true)
    }
}
