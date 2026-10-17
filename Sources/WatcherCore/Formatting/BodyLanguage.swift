import Foundation

/// What a body is, as far as viewing and colouring go.
public enum BodyLanguage: String, CaseIterable, Sendable {
    case json, xml, html, javascript, css, graphql, protobuf, urlencoded, plist
    case http, curl, swift, python, go, ruby, php
    case plain, binary

    /// Guesses the language from a `Content-Type` header, falling back to the first bytes.
    public static func detect(contentType: String?, data: Data) -> BodyLanguage {
        let type = (contentType ?? "").lowercased()
        if type.contains("json") {
            return .json
        }
        if type.contains("graphql") {
            return .graphql
        }
        if type.contains("html") {
            return .html
        }
        if type.contains("xml") && !type.contains("plist") {
            return .xml
        }
        if type.contains("javascript") || type.contains("ecmascript") {
            return .javascript
        }
        if type.contains("css") {
            return .css
        }
        if type.contains("x-www-form-urlencoded") {
            return .urlencoded
        }
        if type.contains("protobuf") || type.contains("grpc") {
            return .protobuf
        }
        if type.contains("plist") {
            return .plist
        }
        if type.hasPrefix("image/") || type.hasPrefix("audio/") || type.hasPrefix("video/") || type.contains("octet-stream") || type.contains("pdf") || type.contains("zip") {
            return .binary
        }
        return sniff(data)
    }

    /// Looks at the first bytes when no usable `Content-Type` is available.
    static func sniff(_ data: Data) -> BodyLanguage {
        guard !data.isEmpty else { return .plain }
        guard let text = String(data: data.prefix(2048), encoding: .utf8) else { return .binary }
        let head = text.drop { $0.isWhitespace }
        if head.hasPrefix("{") || head.hasPrefix("[") {
            return .json
        }
        if head.lowercased().hasPrefix("<!doctype html") || head.lowercased().hasPrefix("<html") {
            return .html
        }
        if head.hasPrefix("<?xml") || head.hasPrefix("<") {
            return .xml
        }
        return .plain
    }
}
