import Foundation

public enum WatcherPaths {
    /// `~/.watcher`, or the folder named by `WATCHER_HOME` (for isolated runs and tests; `HOME` itself is not honoured by Foundation).
    public static var supportDirectory: URL {
        directory(environment: ProcessInfo.processInfo.environment, home: URL(fileURLWithPath: NSHomeDirectory()))
    }

    static func directory(environment: [String: String], home: URL) -> URL {
        if let custom = environment["WATCHER_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent(".watcher", isDirectory: true)
    }
}
