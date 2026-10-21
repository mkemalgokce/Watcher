import Foundation

/// Looking for a newer Watcher and installing it. The app passes the real one (Sparkle, which owns the download, the
/// signature check and the relaunch); a build with nothing to update from passes none, and the app offers no update.
public struct AppUpdater {
    public var check: @MainActor () -> Void
    public var checksAutomatically: @MainActor () -> Bool
    public var setChecksAutomatically: @MainActor (Bool) -> Void

    public init(
        check: @escaping @MainActor () -> Void,
        checksAutomatically: @escaping @MainActor () -> Bool,
        setChecksAutomatically: @escaping @MainActor (Bool) -> Void
    ) {
        self.check = check; self.checksAutomatically = checksAutomatically
        self.setChecksAutomatically = setChecksAutomatically
    }
}

/// Updates are on only in a build that names where to look (an HTTPS feed) and the key that signs what it finds, so
/// `swift run`, tests and previews never reach for a feed they have no way to trust.
public enum UpdateConfiguration {
    public static func isConfigured(_ info: [String: Any]?) -> Bool {
        guard let feed = info?["SUFeedURL"] as? String, let key = info?["SUPublicEDKey"] as? String else {
            return false
        }
        return URL(string: feed)?.scheme == "https" && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
