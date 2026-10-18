import AppKit
import UniformTypeIdentifiers
import WatcherUI

/// Records the files that would have been opened in another app or shown in Finder, and answers which apps open a
/// kind of file with `applications` and `defaultApplication`. `opensFiles` false is a Mac with no app for the file;
/// `openWithFailure` is what opening in a chosen app throws.
@MainActor
public final class WorkspaceOpenerSpy: WorkspaceOpener {
    public private(set) var opened: [URL] = []
    public private(set) var openedWith: [(file: URL, app: URL)] = []
    public private(set) var revealed: [[URL]] = []
    public private(set) var askedTypes: [UTType] = []
    public var applications: [URL]
    public var defaultApplication: URL?
    public var opensFiles = true
    public var openWithFailure: (any Error)?

    public init(applications: [URL] = [], defaultApplication: URL? = nil) {
        self.applications = applications; self.defaultApplication = defaultApplication
    }

    public func open(_ url: URL) -> Bool {
        opened.append(url)
        return opensFiles
    }

    public func open(_ url: URL, withApplicationAt app: URL) async throws {
        openedWith.append((url, app))
        if let openWithFailure {
            throw openWithFailure
        }
    }

    public func reveal(_ urls: [URL]) {
        revealed.append(urls)
    }

    public func applications(toOpen type: UTType) -> [URL] {
        askedTypes.append(type)
        return applications
    }

    public func defaultApplication(toOpen _: UTType) -> URL? {
        defaultApplication
    }

    public func icon(forFile _: String) -> NSImage {
        NSImage()
    }

    public func displayName(ofFile path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
