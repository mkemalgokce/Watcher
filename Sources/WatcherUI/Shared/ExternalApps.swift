import AppKit
import Observation
import UniformTypeIdentifiers
import WatcherCore

/// "Open With" and "Show in Finder" for captured content, saying so when no app takes the file.
@MainActor @Observable
final class ExternalApps {
    private let workspace: any WorkspaceOpener
    private let notices: NoticeCenter
    private let files: FileAccess

    init(workspace: any WorkspaceOpener, notices: NoticeCenter, files: FileAccess) {
        self.workspace = workspace; self.notices = notices; self.files = files
    }

    /// Writes `data` to a file of its own, named `name` (with an extension from the content when it has none), so
    /// another app opens it under a sensible name; the folder is new each time, so no write replaces another.
    func write(_ data: Data, name: String, contentType: String?) throws -> URL {
        let directory = files.temporaryFile("folder").deletingPathExtension()
        try files.createDirectory(directory)
        var base = (name as NSString).deletingPathExtension
        if base.isEmpty || base == "/" {
            base = "body"
        }
        let given = (name as NSString).pathExtension
        let fileExtension = given.isEmpty ? ExternalOpen.fileExtension(contentType: contentType, data: data) : given
        let url = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)
        try files.writeAtomically(data, url)
        return url
    }

    /// Removes a file made by `write` together with the folder made for it.
    func discard(_ url: URL) {
        try? files.remove(url.deletingLastPathComponent())
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
