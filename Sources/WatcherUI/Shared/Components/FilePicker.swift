import Foundation
import UniformTypeIdentifiers
import WatcherCore

/// Picks files for the editors: a multipart upload part, read off the main thread, or the path a Map Local rule serves.
@MainActor
final class FilePicker {
    private let panels: any FilePanels
    private let files: FileAccess

    init(panels: any FilePanels, files: FileAccess) {
        self.panels = panels; self.files = files
    }

    /// Nil means cancelled or unreadable.
    func choosePart() async -> KeyValue.FilePart? {
        guard let url = panels.chooseItem(directory: false) else { return nil }
        let files = files
        let read = Task.detached(priority: .userInitiated) { try files.read(url) }
        guard let data = try? await read.value else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return KeyValue.FilePart(filename: url.lastPathComponent, contentType: type, data: data)
    }

    /// The chosen file, or `current` when the panel is cancelled or the file cannot be read.
    func choosePart(keeping current: KeyValue.FilePart?) async -> KeyValue.FilePart? {
        await choosePart() ?? current
    }

    /// A file or a directory, as the rule's source already is; nil means cancelled.
    func chooseSource(directory: Bool) -> MapLocalRule.Source? {
        guard let url = panels.chooseItem(directory: directory) else { return nil }
        return directory ? .directory(url.path) : .file(url.path)
    }
}
