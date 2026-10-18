import AppKit
import UniformTypeIdentifiers

final class LiveWorkspaceOpener: WorkspaceOpener {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func open(_ url: URL, withApplicationAt app: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func applications(toOpen type: UTType) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: type)
    }

    func defaultApplication(toOpen type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    func icon(forFile path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    func displayName(ofFile path: String) -> String {
        FileManager.default.displayName(atPath: path)
    }
}
