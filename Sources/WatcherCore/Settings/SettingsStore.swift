import Foundation

/// Loads and saves `WatcherSettings`; notices edits made by another process (e.g. the CLI).
///
/// A file that exists but does not decode is moved aside (`settings.json.unreadable-<UTC time>`) so the next
/// save cannot destroy it; `loadIssue` reports that. If it cannot be moved, saves throw while it is still there.
public final class SettingsStore: @unchecked Sendable {
    public let url: URL
    private let files: FileManager
    /// One serial lock around every read and write, so `update` is a single read-change-write step.
    private let lock = NSLock()
    private var current = WatcherSettings()
    private var lastModified: Date?
    private var issue: SettingsLoadIssue?

    public init(url: URL, files: FileManager = .default) {
        self.url = url
        self.files = files
        _ = reloadIfChanged()
    }

    public var value: WatcherSettings {
        lock.withLock { current }
    }

    /// The last settings file that could not be read, or nil once one loads cleanly.
    public var loadIssue: SettingsLoadIssue? {
        lock.withLock { issue }
    }

    /// `change` runs while the store is locked: it must not call back into this store, or it deadlocks.
    public func update(_ change: (inout WatcherSettings) -> Void) throws {
        try lock.withLock {
            var next = current
            change(&next)
            try write(next)
        }
    }

    public func replace(with settings: WatcherSettings) throws {
        try lock.withLock { try write(settings) }
    }

    /// Returns true when the file changed on disk and the in-memory value was refreshed.
    @discardableResult
    public func reloadIfChanged() -> Bool {
        lock.withLock {
            guard let modified = modificationDate, modified != lastModified,
                  let data = try? Data(contentsOf: url) else { return false }
            do {
                current = try JSONDecoder().decode(WatcherSettings.self, from: data)
                lastModified = modified
                issue = nil
                return true
            } catch {
                issue = SettingsLoadIssue(reason: String(describing: error), movedTo: moveAside())
                return false
            }
        }
    }

    /// Caller holds `lock`.
    private func write(_ settings: WatcherSettings) throws {
        if let issue, issue.movedTo == nil, files.fileExists(atPath: url.path) {
            throw SettingsStoreError.unreadableFileInPlace(url)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(settings).write(to: url, options: .atomic)
        // May contain proxy credentials.
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        current = settings
        lastModified = modificationDate
    }

    /// Moves the unreadable file to a name no other backup has; nil when it cannot be moved.
    private func moveAside() -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(url.lastPathComponent).unreadable-\(formatter.string(from: Date()))"
        let directory = url.deletingLastPathComponent()
        for attempt in 1 ... 1000 {
            let target = directory.appendingPathComponent(attempt == 1 ? base : "\(base)-\(attempt)")
            guard !files.fileExists(atPath: target.path) else { continue }
            return (try? files.moveItem(at: url, to: target)) == nil ? nil : target
        }
        return nil
    }

    private var modificationDate: Date? {
        (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

public struct SettingsLoadIssue: Equatable, Sendable {
    /// Why decoding failed.
    public let reason: String
    /// Where the unreadable file now lives; nil when it could not be moved and is still at `SettingsStore.url`.
    public let movedTo: URL?
}

public enum SettingsStoreError: Error, Equatable {
    case unreadableFileInPlace(URL)
}
