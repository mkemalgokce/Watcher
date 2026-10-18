import AppKit
import SwiftUI

/// "Open With" for a body, an uploaded file, an image or a decoded Base64 payload.
struct OpenWithMenu: View {
    @Environment(NoticeCenter.self) private var notices
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
                        let name = app.deletingPathExtension().lastPathComponent
                        Task { @MainActor in
                            notices.notify("Cannot open with \(name): \(error.localizedDescription)", .error)
                        }
                    }
                }
            } else if !NSWorkspace.shared.open(url) {
                notices.notify("No app opens \(url.pathExtension) files. Use Open With to pick one.", .error)
            }
        } catch { notices.notify("Cannot prepare the file: \(error.localizedDescription)", .error) }
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
