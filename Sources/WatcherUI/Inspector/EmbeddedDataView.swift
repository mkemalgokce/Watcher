import AppKit
import SwiftUI
import WatcherCore

/// The Decoded section: every embedded payload with a preview and the actions a developer needs (save, open, copy).
struct EmbeddedDataView: View {
    @Environment(RequestActions.self) private var actions
    @Environment(SessionFilesViewModel.self) private var sessionFiles
    let segments: [Base64Segment]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Label("\(segments.count) Base64 payload\(segments.count == 1 ? "" : "s") decoded from this body", systemImage: "wand.and.stars")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(segments) { segment in
                    Card(title: segment.label ?? segment.kindName, symbol: segment.symbol) {
                        actions(segment)
                    } content: {
                        preview(segment)
                        Text("\(segment.kindName) · \(Format.bytes(segment.data.count))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private func preview(_ segment: Base64Segment) -> some View {
        if segment.isPDF {
            RichPreview(kind: .pdf, data: segment.data, contentType: "application/pdf").frame(height: 320)
        } else {
            kindPreview(segment)
        }
    }

    @ViewBuilder private func kindPreview(_ segment: Base64Segment) -> some View {
        switch segment.kind {
        case let .image(mime):
            ImagePreview(data: segment.data, mime: mime).frame(maxWidth: .infinity, minHeight: 120, maxHeight: 280)
        case .text:
            let text = segment.text ?? String(decoding: segment.data, as: UTF8.self)
            if JSONTree.isDocument(text) {
                JSONDocumentView(source: text).frame(height: 300)
            } else {
                let language = BodyLanguage.detect(contentType: segment.mimeType, data: Data(text.utf8))
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
                SyntaxTextView(text, language: language)
                    .frame(height: min(260, max(60, CGFloat(lines) * 16 + 20)))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
            }
        case .binary:
            SyntaxTextView(BodyFormatter.hexDump(segment.data, limit: 2048), language: .binary, wraps: false).frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
        }
    }

    private func actions(_ segment: Base64Segment) -> some View {
        HStack(spacing: 2) {
            // The image preview has its own copy, save and open buttons; repeating them on the card would show each twice.
            if !segment.isImage {
                IconButton("Save \(segment.kindName)…", symbol: "square.and.arrow.down") {
                    sessionFiles.saveData(segment.data, suggestedName: segment.suggestedFileName)
                }
                OpenWithMenu(data: segment.data, name: segment.suggestedFileName, contentType: segment.mimeType)
                    .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Open the decoded \(segment.kindName.lowercased()) in another app")
            }
            Menu {
                if case .image = segment.kind, let image = NSImage(data: segment.data) {
                    Button("Copy Image") { actions.copy(image: image) }
                }
                if let text = segment.text {
                    Button("Copy Decoded Text") { actions.copy(text, "Decoded text copied") }
                }
                Button("Copy as Base64") { actions.copy(segment.data.base64EncodedString(), "Base64 copied") }
                Button("Copy as Data URI") { actions.copy("data:\(segment.mimeType);base64,\(segment.data.base64EncodedString())", "Data URI copied") }
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 15, weight: .regular)).frame(width: Metrics.iconButton, height: Metrics.iconButton)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Copy the decoded data")
        }
    }
}
