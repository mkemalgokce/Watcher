import SwiftUI
import WatcherCore

/// What a body can be shown as besides text.
enum RichKind: Equatable {
    case image, html, pdf, media, eventStream, form

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
        return nil
    }
}
