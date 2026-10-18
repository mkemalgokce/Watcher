import SwiftUI

/// "Open With" for a body, an uploaded file, an image or a decoded Base64 payload.
struct OpenWithMenu: View {
    @Environment(NoticeCenter.self) private var notices
    @Environment(ExternalApps.self) private var externalApps
    let data: Data
    var name = "body"
    var contentType: String?
    var title = "Open With"

    var body: some View {
        Menu(title, systemImage: "arrow.up.forward.app") {
            Button("Open in Default App") { open(with: nil) }
            Divider()
            ForEach(externalApps.applications(contentType: contentType, data: data), id: \.self) { app in
                Button {
                    open(with: app)
                } label: {
                    Label { Text(externalApps.name(of: app)) } icon: { Image(nsImage: externalApps.icon(of: app)) }
                }
            }
            Divider()
            Button("Show in Finder", systemImage: "folder") {
                guard let url = try? externalApps.write(data, name: name, contentType: contentType) else { return }
                externalApps.reveal(url)
            }
        }
        .disabled(data.isEmpty)
    }

    private func open(with app: URL?) {
        do {
            let url = try externalApps.write(data, name: name, contentType: contentType)
            Task { await externalApps.open(url, with: app) }
        } catch { notices.notify("Cannot prepare the file: \(error.localizedDescription)", .error) }
    }
}

extension View {
    /// Lets the content be dragged into Finder or another app as a file.
    func draggableFile(
        _ data: Data, name: String, contentType: String?, using externalApps: ExternalApps
    ) -> some View {
        onDrag {
            guard let url = try? externalApps.write(data, name: name, contentType: contentType) else {
                return NSItemProvider()
            }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }
}
