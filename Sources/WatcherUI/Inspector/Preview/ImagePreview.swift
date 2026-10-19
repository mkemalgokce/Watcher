import AppKit
import SwiftUI
import WatcherCore

/// An image from a response or a Base64 field, on a checkerboard so transparency is visible, with size info and save/copy.
struct ImagePreview: View {
    @Environment(RequestActions.self) private var actions
    @Environment(SessionFilesViewModel.self) private var sessionFiles
    @Environment(ExternalApps.self) private var externalApps
    let data: Data
    var mime: String?
    @State private var actualSize = false

    private var image: NSImage? {
        NSImage(data: data)
    }

    var body: some View {
        if let image {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(summary(image)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Size", selection: $actualSize) { Text("Fit").tag(false); Text("Actual").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 120).accessibilityLabel("Image size")
                    Button("Copy Image", systemImage: "doc.on.doc") {
                        actions.copy(image: image)
                    }.labelStyle(.iconOnly).help("Copy image")
                    Button("Save Image…", systemImage: "square.and.arrow.down") { save() }.labelStyle(.iconOnly).help("Save image…")
                    OpenWithMenu(data: data, name: "image", contentType: mime).labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
                        .help("Open in Preview or another app")
                }
                ScrollView(actualSize ? [.horizontal, .vertical] : []) {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: actualSize ? image.size.width : nil, height: actualSize ? image.size.height : nil)
                        .frame(maxWidth: actualSize ? nil : .infinity, maxHeight: actualSize ? nil : .infinity)
                        .padding(8)
                        .accessibilityLabel("Image, \(Int(image.size.width)) by \(Int(image.size.height)) pixels")
                }
                .background(Checkerboard()).clipShape(RoundedRectangle(cornerRadius: 6))
                .draggableFile(data, name: "image", contentType: mime, using: externalApps)
                .help("Drag the image to Finder or another app")
            }
        } else {
            ContentUnavailableView(
                "Cannot display this image",
                systemImage: "photo.badge.exclamationmark",
                description: Text("The data is \(Format.bytes(data.count)) and is not a format macOS can draw. Use Raw or Hex to inspect it.")
            )
        }
    }

    private func summary(_ image: NSImage) -> String {
        let size = image.representations.first.map { (width: $0.pixelsWide, height: $0.pixelsHigh) }
            ?? (width: Int(image.size.width), height: Int(image.size.height))
        return ImageInfo.summary(width: size.width, height: size.height, declaredMime: mime, data: data)
    }

    private func save() {
        let ext = FileExtension.preferred(forContentType: ImageInfo.mime(declared: mime, data: data)) ?? "png"
        sessionFiles.saveData(data, suggestedName: "image.\(ext)")
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            for row in 0 ..< Int(size.height / cell) + 1 {
                for column in 0 ..< Int(size.width / cell) + 1 where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(.secondary.opacity(0.14)))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor)).accessibilityHidden(true)
    }
}
