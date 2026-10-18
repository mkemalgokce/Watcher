import AppKit
import Observation
import UniformTypeIdentifiers

/// "Open With" and "Show in Finder" for captured content, saying so when no app takes the file.
@MainActor @Observable
final class ExternalApps {
    private let workspace: any WorkspaceOpener
    private let notices: NoticeCenter

    init(workspace: any WorkspaceOpener, notices: NoticeCenter) {
        self.workspace = workspace; self.notices = notices
    }

    /// Apps that say they can open this kind of content, the default one first.
    func applications(contentType: String?, data: Data) -> [URL] {
        let fileExtension = ExternalOpen.fileExtension(contentType: contentType, data: data)
        guard let type = UTType(filenameExtension: fileExtension) else { return [] }
        let preferred = workspace.defaultApplication(toOpen: type)
        let others = workspace.applications(toOpen: type).filter { $0 != preferred }.prefix(12)
        return (preferred.map { [$0] } ?? []) + others
    }

    func icon(of app: URL) -> NSImage {
        workspace.icon(forFile: app.path)
    }

    func name(of app: URL) -> String {
        workspace.displayName(ofFile: app.path)
    }

    /// Opens the file in `app`, or in its default app when nil.
    func open(_ url: URL, with app: URL?) async {
        guard let app else {
            if !workspace.open(url) {
                notices.notify("No app opens \(url.pathExtension) files. Use Open With to pick one.", .error)
            }
            return
        }
        do {
            try await workspace.open(url, withApplicationAt: app)
        } catch {
            let name = app.deletingPathExtension().lastPathComponent
            notices.notify("Cannot open with \(name): \(error.localizedDescription)", .error)
        }
    }

    func reveal(_ url: URL) {
        workspace.reveal([url])
    }
}
