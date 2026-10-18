import Foundation
import WatcherCore

public extension WatcherEngine {
    /// An engine whose root certificate, settings and workspaces live in `files` instead of on disk.
    static func inMemory(files: FileAccessFake = FileAccessFake()) throws -> WatcherEngine {
        try WatcherEngine(directory: URL(fileURLWithPath: "/fake-home/.watcher"), files: files.access)
    }
}
