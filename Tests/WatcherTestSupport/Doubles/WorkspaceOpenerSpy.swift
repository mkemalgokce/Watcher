import Foundation
import WatcherUI

/// Records the files that would have been opened in another app or shown in Finder.
@MainActor
public final class WorkspaceOpenerSpy: WorkspaceOpener {
    public private(set) var opened: [URL] = []
    public private(set) var revealed: [[URL]] = []

    public init() {}

    public func open(_ url: URL) {
        opened.append(url)
    }

    public func reveal(_ urls: [URL]) {
        revealed.append(urls)
    }
}
