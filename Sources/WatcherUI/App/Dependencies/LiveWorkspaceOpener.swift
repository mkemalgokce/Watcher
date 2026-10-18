import AppKit

final class LiveWorkspaceOpener: WorkspaceOpener {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
