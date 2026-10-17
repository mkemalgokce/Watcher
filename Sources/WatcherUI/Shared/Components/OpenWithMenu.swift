import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WatcherCore

/// Hands captured content to other apps: written once to a temporary file with the right extension, then opened.
@MainActor
enum ExternalOpen {
    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Watcher Open", isDirectory: true)
    }

    static func fileExtension(contentType: String?, data: Data) -> String {
        let media = contentType?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if let ext = UTType(mimeType: media)?.preferredFilenameExtension {
            return ext
        }
        if let image = Base64Finder.imageMime(data), let ext = UTType(mimeType: image)?.preferredFilenameExtension {
            return ext
        }
        return String(data: data.prefix(4096), encoding: .utf8) != nil ? "txt" : "bin"
    }

    static func write(_ data: Data, name: String, contentType: String?) throws -> URL {
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var base = (name as NSString).deletingPathExtension
        if base.isEmpty || base == "/" {
            base = "body"
        }
        let given = (name as NSString).pathExtension
        let url = directory.appendingPathComponent(base).appendingPathExtension(given.isEmpty ? fileExtension(contentType: contentType, data: data) : given)
        try data.write(to: url)
        return url
    }

    /// Apps that say they can open this kind of file, the default one first.
    static func apps(contentType: String?, data: Data) -> [URL] {
        guard let type = UTType(filenameExtension: fileExtension(contentType: contentType, data: data)) else { return [] }
        let all = NSWorkspace.shared.urlsForApplications(toOpen: type)
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: type)
        return (preferred.map { [$0] } ?? []) + all.filter { $0 != preferred }.prefix(12)
    }
}

/// "Open With" for a body, an uploaded file, an image or a decoded Base64 payload.
struct OpenWithMenu: View {
    @Environment(AppModel.self) private var model
    let data: Data
    var name = "body"
    var contentType: String?
    var title = "Open With"

    var body: some View {
        Menu(title, systemImage: "arrow.up.forward.app") {
            Button("Open in Default App") { open(with: nil) }
            Divider()
            ForEach(ExternalOpen.apps(contentType: contentType, data: data), id: \.self) { app in
                Button {
                    open(with: app)
                } label: {
                    Label { Text(FileManager.default.displayName(atPath: app.path)) } icon: { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)) }
                }
            }
            Divider()
            Button("Show in Finder", systemImage: "folder") {
                guard let url = try? ExternalOpen.write(data, name: name, contentType: contentType) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .disabled(data.isEmpty)
    }

    private func open(with app: URL?) {
        do {
            let url = try ExternalOpen.write(data, name: name, contentType: contentType)
            if let app {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error {
                        Task { @MainActor in model.errorMessage = "Cannot open with \(app.deletingPathExtension().lastPathComponent): \(error.localizedDescription)" }
                    }
                }
            } else if !NSWorkspace.shared.open(url) {
                model.errorMessage = "No app opens \(url.pathExtension) files. Use Open With to pick one."
            }
        } catch { model.errorMessage = "Cannot prepare the file: \(error.localizedDescription)" }
    }
}

extension View {
    /// Lets the content be dragged into Finder or another app as a file.
    func draggableFile(_ data: Data, name: String, contentType: String?) -> some View {
        onDrag {
            guard let url = try? ExternalOpen.write(data, name: name, contentType: contentType) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }
}
