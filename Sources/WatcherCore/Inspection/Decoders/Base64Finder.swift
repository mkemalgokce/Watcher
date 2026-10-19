import Foundation

/// A Base64 payload found inside a body, with what it turned out to contain.
public struct Base64Segment: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case image(mime: String), text, binary }

    /// Where the encoded text sits in the searched string (UTF-16 offsets).
    public let range: NSRange
    public let data: Data
    public let kind: Kind
    /// The decoded text for `.text`, pretty-printed when it is JSON.
    public let text: String?
    /// Label for the list: the JSON key or `data:` URI media type, when known.
    public let label: String?

    /// Found segments never overlap, so where one starts identifies it, and the same text gives the same ids.
    public var id: Int {
        range.location
    }

    public static func == (a: Base64Segment, b: Base64Segment) -> Bool {
        a.range == b.range && a.data == b.data
    }
}

public enum Base64Finder {
    /// Shortest string treated as Base64: shorter ones (ids, hashes, words) are rarely worth decoding.
    static let minimumLength = 24

    /// Every decodable Base64 payload in `text`: `data:` URIs and long Base64-looking JSON string values or the whole text.
    public static func find(in text: String) -> [Base64Segment] {
        let ns = text as NSString
        var found: [Base64Segment] = []
        var claimed: [NSRange] = []

        func add(_ range: NSRange, encoded: String, label: String?, mime: String? = nil) {
            guard !claimed.contains(where: { NSIntersectionRange($0, range).length > 0 }), let data = decode(encoded), !data.isEmpty else { return }
            claimed.append(range)
            let kind = classify(data, declaredMime: mime)
            var decodedText: String?
            if kind == .text, let string = String(data: data, encoding: .utf8) {
                decodedText = JSONFormatter.looksLikeJSON(string) ? JSONFormatter.pretty(string) : string
            }
            found.append(Base64Segment(range: range, data: data, kind: kind, text: decodedText, label: label))
        }

        for match in matches(dataURI, in: text) {
            add(match.range(at: 2), encoded: ns.substring(with: match.range(at: 2)), label: ns.substring(with: match.range(at: 1)), mime: ns.substring(with: match.range(at: 1)))
        }
        for match in matches(jsonValue, in: text) {
            add(match.range(at: 2), encoded: ns.substring(with: match.range(at: 2)), label: ns.substring(with: match.range(at: 1)))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if found.isEmpty, trimmed.count >= minimumLength, trimmed.range(of: #"^[A-Za-z0-9+/_\s-]+={0,2}$"#, options: .regularExpression) != nil {
            add(NSRange(location: 0, length: ns.length), encoded: trimmed, label: nil)
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// Standard and URL-safe alphabets, with or without padding, line breaks ignored.
    public static func decode(_ string: String) -> Data? {
        var s = string.filter { !$0.isWhitespace }.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 {
            s += "="
        }
        return Data(base64Encoded: s)
    }

    /// Media type from the first bytes; nil when it is not a known image.
    public static func imageMime(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if b.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "image/gif"
        }
        if b.count >= 12, b[0 ..< 4] == [0x52, 0x49, 0x46, 0x46], b[8 ..< 12] == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        if b.starts(with: [0x42, 0x4D]) {
            return "image/bmp"
        }
        if b.starts(with: [0x49, 0x49, 0x2A, 0x00]) || b.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "image/tiff"
        }
        if String(data: data.prefix(256), encoding: .utf8)?.contains("<svg") == true {
            return "image/svg+xml"
        }
        return nil
    }

    private static func classify(_ data: Data, declaredMime: String?) -> Base64Segment.Kind {
        if let mime = imageMime(data) ?? declaredMime.flatMap({ $0.hasPrefix("image/") ? $0 : nil }) {
            return .image(mime: mime)
        }
        if let string = String(data: data, encoding: .utf8), !string.contains("\u{0}"),
           string.unicodeScalars.filter({ $0.value < 32 && !"\n\r\t".unicodeScalars.contains($0) }).isEmpty
        {
            return .text
        }
        return .binary
    }

    private static let dataURI = try? NSRegularExpression(pattern: #"data:([\w.+/-]+);base64,([A-Za-z0-9+/_=-]+)"#)
    private static let jsonValue = try? NSRegularExpression(
        pattern: #""([A-Za-z0-9_.-]+)"\s*:\s*"([A-Za-z0-9+/_-]{\#(minimumLength),}={0,2})""#
    )

    private static func matches(_ regex: NSRegularExpression?, in text: String) -> [NSTextCheckingResult] {
        regex?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? []
    }
}
