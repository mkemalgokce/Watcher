import AppKit
import UniformTypeIdentifiers

/// Hands files to other apps and Finder, and says which apps open a kind of file.
@MainActor
public protocol WorkspaceOpener: AnyObject {
    /// Opens the file in its default app; false when no app opens it.
    @discardableResult
    func open(_ url: URL) -> Bool
    func open(_ url: URL, withApplicationAt app: URL) async throws
    func reveal(_ urls: [URL])
    func applications(toOpen type: UTType) -> [URL]
    func defaultApplication(toOpen type: UTType) -> URL?
    func icon(forFile path: String) -> NSImage
    /// The name Finder shows, such as "Preview" for Preview.app.
    func displayName(ofFile path: String) -> String
}
