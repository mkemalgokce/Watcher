import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WatcherCore

/// Base64 payloads hidden inside a body (JSON values, `data:` URIs, a whole body that is Base64): found once per body,
/// then kept, so the section tab and its badge cost nothing on later redraws.
@MainActor
final class EmbeddedDataIndex {
    static let shared = EmbeddedDataIndex()

    struct Key: Hashable { let flow: UUID; let side: MessageSide; let size: Int }

    /// Bodies beyond this are not searched: finding Base64 is a regular-expression pass over the whole text.
    nonisolated static let scanLimit = 2 * 1024 * 1024
    private static let capacity = 300

    private var cache: [Key: [Base64Segment]] = [:]
    private var order: [Key] = []

    func segments(in flow: Flow, side: MessageSide) -> [Base64Segment] {
        let headers = side == .request ? flow.request.headers : flow.response?.headers ?? []
        let body = side == .request ? flow.request.body : flow.response?.body ?? Data()
        let key = Key(flow: flow.id, side: side, size: body.count)
        if let known = cache[key] {
            return known
        }
        let found = Self.scan(body, contentEncoding: headers.value(for: "content-encoding"))
        cache[key] = found
        order.append(key)
        if order.count > Self.capacity {
            cache.removeValue(forKey: order.removeFirst())
        }
        return found
    }

    nonisolated static func scan(_ body: Data, contentEncoding: String?) -> [Base64Segment] {
        guard !body.isEmpty else { return [] }
        let data = BodyDecoder.decode(body, contentEncoding: contentEncoding).data
        guard data.count <= scanLimit, let text = String(data: data, encoding: .utf8) else { return [] }
        return Base64Finder.find(in: text)
    }
}

extension Base64Segment {
    var isPDF: Bool {
        data.starts(with: Data("%PDF".utf8))
    }

    var isImage: Bool {
        if case .image = kind {
            true
        } else {
            false
        }
    }

    /// The media type of what was decoded, for previews, Open With and the saved file's extension.
    var mimeType: String {
        if isPDF {
            return "application/pdf"
        } // a small PDF can be all text, so its signature wins over the text/binary guess
        return switch kind {
        case let .image(mime): mime
        case .text: (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil ? "application/json" : "text/plain"
        case .binary: isPDF ? "application/pdf" : "application/octet-stream"
        }
    }

    var kindName: String {
        if isPDF {
            return "PDF"
        }
        return switch kind {
        case let .image(mime): mime.replacingOccurrences(of: "image/", with: "").uppercased() + " image"
        case .text: mimeType == "application/json" ? "JSON" : "Text"
        case .binary: isPDF ? "PDF" : "Binary"
        }
    }

    var symbol: String {
        if isPDF {
            return "doc.richtext"
        }
        return switch kind {
        case .image: "photo"
        case .text: mimeType == "application/json" ? "curlybraces" : "doc.text"
        case .binary: isPDF ? "doc.richtext" : "number.square"
        }
    }

    /// A file name for saving: the JSON key when there is one, with the extension of the decoded type.
    var suggestedFileName: String {
        let base = (label ?? "decoded").replacingOccurrences(of: "/", with: "-")
        let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? (isPDF ? "pdf" : "bin")
        return base.hasSuffix(".\(ext)") ? base : "\(base).\(ext)"
    }
}

/// The Decoded section: every embedded payload with a preview and the actions a developer needs (save, open, copy).
struct EmbeddedDataView: View {
    @Environment(AppModel.self) private var model
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
            SyntaxTextView(text, language: BodyLanguage.detect(contentType: segment.mimeType, data: Data(text.utf8)))
                .frame(height: min(260, max(60, CGFloat(text.split(separator: "\n", omittingEmptySubsequences: false).count) * 16 + 20)))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
        case .binary:
            SyntaxTextView(BodyFormatter.hexDump(segment.data, limit: 2048), language: .binary, wraps: false).frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
        }
    }

    private func actions(_ segment: Base64Segment) -> some View {
        HStack(spacing: 2) {
            // The image preview has its own copy, save and open buttons; repeating them on the card would show each twice.
            if !segment.isImage {
                IconButton("Save \(segment.kindName)…", symbol: "square.and.arrow.down") { model.saveData(segment.data, suggestedName: segment.suggestedFileName) }
                OpenWithMenu(data: segment.data, name: segment.suggestedFileName, contentType: segment.mimeType)
                    .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Open the decoded \(segment.kindName.lowercased()) in another app")
            }
            Menu {
                if case .image = segment.kind, let image = NSImage(data: segment.data) {
                    Button("Copy Image") { model.pasteboard.clearContents(); model.pasteboard.writeObjects([image]); model.notify("Image copied", .success) }
                }
                if let text = segment.text {
                    Button("Copy Decoded Text") { model.copy(text, "Decoded text copied") }
                }
                Button("Copy as Base64") { model.copy(segment.data.base64EncodedString(), "Base64 copied") }
                Button("Copy as Data URI") { model.copy("data:\(segment.mimeType);base64,\(segment.data.base64EncodedString())", "Data URI copied") }
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 15, weight: .regular)).frame(width: Metrics.iconButton, height: Metrics.iconButton)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Copy the decoded data")
        }
    }
}
