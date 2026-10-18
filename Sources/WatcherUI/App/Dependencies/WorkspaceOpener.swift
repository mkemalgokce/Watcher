import Foundation

/// Hands files to other apps and Finder.
@MainActor
public protocol WorkspaceOpener: AnyObject {
    func open(_ url: URL)
    func reveal(_ urls: [URL])
}
