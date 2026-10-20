import SwiftUI
import WatcherCore

/// What a body can be shown as besides text.
enum RichKind: Equatable {
    case image, html, pdf, media, eventStream, form, json, yaml

    static func of(contentType: String?, data: Data) -> RichKind? {
        let type = (contentType ?? "").lowercased()
        if type.contains("multipart/form-data") || type.contains("x-www-form-urlencoded") {
            return .form
        }
        if type.hasPrefix("image/") || Base64Finder.imageMime(data) != nil {
            return .image
        }
        if type.contains("text/html") {
            return .html
        }
        if type.contains("application/pdf") || data.starts(with: Data("%PDF".utf8)) {
            return .pdf
        }
        if type.hasPrefix("audio/") || type.hasPrefix("video/") {
            return .media
        }
        if type.contains("text/event-stream") {
            return .eventStream
        }
        // Only the header says YAML: a bare word or sentence is valid YAML too, so sniffing would call any text a tree.
        if type.contains("yaml") {
            return .yaml
        }
        // A JSON header is believed as it is. Without one the bytes are sniffed, and only a body that parses counts,
        // so prose that starts with a bracket does not get a tree.
        if type.contains("json") {
            return .json
        }
        let sniffedJSON = BodyLanguage.detect(contentType: contentType, data: data) == .json
            && String(data: data, encoding: .utf8).map(JSONTree.isDocument) == true
        return sniffedJSON ? .json : nil
    }
}

extension RichKind {
    /// Rendered as a tree of folding rows rather than by a previewer of its own.
    var isTree: Bool {
        self == .json || self == .yaml
    }
}
