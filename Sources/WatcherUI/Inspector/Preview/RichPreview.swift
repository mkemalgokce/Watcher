import AVKit
import SwiftUI
import UniformTypeIdentifiers
import WatcherCore

struct RichPreview: View {
    let kind: RichKind
    let data: Data
    let contentType: String?

    var body: some View {
        switch kind {
        case .image: ImagePreview(data: data, mime: contentType)
        case .html: HTMLPreview(html: String(decoding: data, as: UTF8.self))
        case .pdf: PDFPreview(data: data)
        case .media: MediaPreview(data: data, contentType: contentType)
        case .eventStream: EventStreamView(text: String(decoding: data, as: UTF8.self))
        case .form:
            // Parsed like a request body; the query part of the path is irrelevant here.
            let fields = FormFields.parse(RequestRecord(
                method: "POST",
                scheme: "https",
                host: "body",
                port: 443,
                path: "/",
                headers: contentType.map { [Header("Content-Type", $0)] } ?? [],
                body: data
            ))
            KeyValueTable(rows: KeyValueRow.fields(fields), emptyText: "No fields could be read from this body.").padding(8)
        }
    }
}

/// Audio and video play from a temporary file (AVPlayer needs a URL); the file is removed when the view goes away.
private struct MediaPreview: View {
    let data: Data
    let contentType: String?
    @State private var player: AVPlayer?
    @State private var file: URL?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .onAppear {
            let ext = UTType(mimeType: contentType ?? "")?.preferredFilenameExtension ?? "bin"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-media-\(UUID().uuidString).\(ext)")
            if (try? data.write(to: url)) != nil {
                file = url; player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause(); if let file {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

/// Server-Sent Events as a list, one row per event, data coloured as JSON when it is JSON.
private struct EventStreamView: View {
    let text: String

    var body: some View {
        let events = EventStream.parse(text)
        if events.isEmpty {
            ContentUnavailableView("No events yet", systemImage: "dot.radiowaves.left.and.right", description: Text("The stream has not sent a complete event."))
        } else {
            List(Array(events.enumerated()), id: \.offset) { index, event in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("#\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if let name = event.event {
                            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Palette.modified)
                        }
                        if let id = event.id {
                            Text("id \(id)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(event.data.isEmpty ? "(no data)" : event.data).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .foregroundStyle(event.data.hasPrefix("{") ? Color(nsColor: SyntaxTextView.Theme.color(.string)) : .primary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
