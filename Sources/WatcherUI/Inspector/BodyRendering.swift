import Foundation
import WatcherCore

/// What a body viewer shows for one body and the chosen options. Pure, so large bodies can be prepared off the main
/// thread.
enum BodyRendering {
    /// Text longer than this is shown cut off; the whole body can still be saved or copied from the menu.
    static let displayLimit = 16 * 1024 * 1024

    struct UnpackKey: Hashable, Sendable { let flow: UUID; let side: MessageSide; let size: Int }

    /// The body after Content-Encoding is undone, and what it can be rendered as.
    struct Unpacked: Equatable {
        let id: UnpackKey
        let data: Data
        let richKind: RichKind?
    }

    struct Prepared: Equatable {
        var text: String
        var language: BodyLanguage
        var note: String?
        var cutFrom: Int?
        var pathFailed = false
    }

    static func unpack(_ key: UnpackKey, _ payload: Data, contentType: String?, encoding: String?) -> Unpacked {
        let data = BodyDecoder.decode(payload, contentEncoding: encoding).data
        let richKind = payload.isEmpty ? nil : RichKind.of(contentType: contentType, data: data)
        return Unpacked(id: key, data: data, richKind: richKind)
    }

    /// The text for a text mode, filtered by `path` when the body is JSON, and cut to `limit` bytes on a whole line.
    static func prepare(
        _ payload: Data,
        contentType: String?,
        encoding: String? = nil,
        mode: BodyMode,
        sortKeys: Bool,
        path: String = "",
        limit: Int? = displayLimit
    ) -> Prepared {
        var result: Prepared
        switch mode {
        case .hex: result = Prepared(text: BodyFormatter.hexDump(payload), language: .binary)
        case .raw:
            result = Prepared(
                text: String(data: payload, encoding: .utf8) ?? BodyFormatter.hexDump(payload),
                language: BodyLanguage.detect(contentType: contentType, data: payload),
                note: "raw"
            )
        case .pretty, .preview:
            let formatted = BodyFormatter.format(
                payload, contentType: contentType, contentEncoding: encoding, sortKeys: sortKeys
            )
            result = Prepared(text: formatted.text, language: formatted.language, note: formatted.note)
        }
        if result.language == .json, !path.isEmpty {
            let filtered = JQ.looksLikeJQ(path) ? JQ.run(path, on: payload) : JSONQuery.run(path, on: payload)
            if let filtered {
                result.text = filtered
            } else {
                result.pathFailed = true
            }
        }
        if let limit, result.text.utf8.count > limit {
            result.cutFrom = result.text.utf8.count
            // swiftlint:disable:next optional_data_string_conversion
            var cut = String(decoding: result.text.utf8.prefix(limit), as: UTF8.self) // a cut mid-character still reads
            if let newline = cut.lastIndex(of: "\n") {
                cut = String(cut[..<newline])
            }
            result.text = cut
        }
        return result
    }

    /// The chosen mode, falling back to Pretty when the body has nothing to render.
    static func effectiveMode(chosen: BodyMode, richKind: RichKind?) -> BodyMode {
        chosen == .preview && richKind == nil ? .pretty : chosen
    }

    static func modes(richKind: RichKind?) -> [BodyMode] {
        BodyMode.allCases.filter { $0 != .preview || richKind != nil }
    }

    /// The line beside the mode tabs: what is rendered, or the language and how it was formatted.
    static func summary(mode: BodyMode, richKind: RichKind?, prepared: Prepared?) -> String {
        if mode == .preview, let richKind {
            return switch richKind {
            case .image: "Image"
            case .html: "HTML, rendered offline"
            case .pdf: "PDF"
            case .media: "Audio / video"
            case .eventStream: "Server-Sent Events"
            case .form: "Form fields"
            }
        }
        return ([prepared?.language.displayName ?? "…"] + [prepared?.note].compactMap(\.self)).joined(separator: " · ")
    }
}
