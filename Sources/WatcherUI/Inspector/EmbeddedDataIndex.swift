import UniformTypeIdentifiers
import WatcherCore

/// Base64 payloads hidden inside a body (JSON values, `data:` URIs, a whole body that is Base64): found once per body,
/// then kept, so the section tab and its badge cost nothing on later redraws.
@MainActor
final class EmbeddedDataIndex {
    struct Key: Hashable { let flow: UUID; let side: MessageSide; let size: Int }

    /// Bodies beyond this are not searched: finding Base64 is a regular-expression pass over the whole text.
    nonisolated static let scanLimit = 2 * 1024 * 1024
    private static let capacity = 300

    private var cache: [Key: [Base64Segment]] = [:]
    private var order: [Key] = []

    func segments(in flow: Flow, side: MessageSide) -> [Base64Segment] {
        let headers = flow.headers(side), body = flow.body(side)
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
        case .binary: "application/octet-stream"
        }
    }

    var kindName: String {
        if isPDF {
            return "PDF"
        }
        return switch kind {
        case let .image(mime): mime.replacingOccurrences(of: "image/", with: "").uppercased() + " image"
        case .text: mimeType == "application/json" ? "JSON" : "Text"
        case .binary: "Binary"
        }
    }

    var symbol: String {
        if isPDF {
            return "doc.richtext"
        }
        return switch kind {
        case .image: "photo"
        case .text: mimeType == "application/json" ? "curlybraces" : "doc.text"
        case .binary: "number.square"
        }
    }

    /// A file name for saving: the JSON key when there is one, with the extension of the decoded type.
    var suggestedFileName: String {
        let base = (label ?? "decoded").replacingOccurrences(of: "/", with: "-")
        let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "bin"
        return base.hasSuffix(".\(ext)") ? base : "\(base).\(ext)"
    }
}
