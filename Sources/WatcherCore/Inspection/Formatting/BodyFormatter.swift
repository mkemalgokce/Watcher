import Foundation

public struct FormattedBody: Sendable, Equatable {
    public let text: String
    public let language: BodyLanguage
    /// A short remark shown next to the body, e.g. "decoded from gzip".
    public let note: String?

    public init(text: String, language: BodyLanguage, note: String?) {
        self.text = text; self.language = language; self.note = note
    }
}

/// Turns a captured body into text a person can read.
public enum BodyFormatter {
    /// Bodies above this are shown as they are; pretty-printing megabytes of JSON would freeze the viewer.
    static let prettyLimit = 64 * 1024 * 1024

    public static func format(
        _ data: Data, contentType: String?, contentEncoding: String? = nil, sortKeys: Bool = false,
        detectsGraphQL: Bool = true
    ) -> FormattedBody {
        let decoded = BodyDecoder.decode(data, contentEncoding: contentEncoding)
        let note = decoded.removedEncoding.map { "decoded from \($0)" }
        let body = decoded.data
        guard !body.isEmpty else { return FormattedBody(text: "", language: .plain, note: note) }

        let language = BodyLanguage.detect(contentType: contentType, data: body)
        if language == .binary {
            return FormattedBody(text: hexDump(body), language: .binary, note: note ?? "\(body.count) bytes")
        }
        guard let text = String(data: body, encoding: .utf8) else { return FormattedBody(text: hexDump(body), language: .binary, note: note ?? "not UTF-8") }
        if body.count > prettyLimit {
            return FormattedBody(text: text, language: language, note: "too large to format")
        }

        let options = JSONOptions(sortKeys: sortKeys, detectsGraphQL: detectsGraphQL)
        return render(body, text: text, language: language, note: note, json: options)
    }

    private struct JSONOptions {
        let sortKeys: Bool
        let detectsGraphQL: Bool
    }

    private static func render(
        _ body: Data, text: String, language: BodyLanguage, note: String?, json: JSONOptions
    ) -> FormattedBody {
        switch language {
        case .json:
            formatJSON(body, text: text, note: note, options: json)
        case .xml, .html:
            formatMarkup(body, text: text, language: language, note: note)
        case .javascript, .css:
            FormattedBody(text: CodeBeautifier.beautify(text), language: language, note: note)
        case .urlencoded:
            FormattedBody(text: urlEncodedLines(text), language: .urlencoded, note: note)
        case .plist:
            FormattedBody(text: plistText(body) ?? text, language: .xml, note: note)
        case .protobuf:
            FormattedBody(text: ProtobufWire.describe(body) ?? hexDump(body), language: .protobuf, note: note)
        default:
            FormattedBody(text: text, language: language, note: note)
        }
    }

    /// Markup that does not parse is shown as plain text, not as broken XML.
    private static func formatMarkup(
        _ body: Data, text: String, language: BodyLanguage, note: String?
    ) -> FormattedBody {
        let pretty = prettyXML(body, html: language == .html)
        let shown = pretty == nil && language == .xml ? BodyLanguage.plain : language
        return FormattedBody(text: pretty ?? text, language: shown, note: note)
    }

    private static func formatJSON(
        _ body: Data, text: String, note: String?, options: JSONOptions
    ) -> FormattedBody {
        if options.detectsGraphQL, body.count < 1_000_000, let graphQL = BodyPreview.graphQL(body) {
            return FormattedBody(text: graphQL, language: .graphql, note: note)
        }
        if options.sortKeys, let sorted = JSONFormatter.sortedKeys(body) {
            return FormattedBody(text: sorted, language: .json, note: note)
        }
        let pretty = JSONFormatter.looksLikeJSON(text) ? JSONFormatter.prettyData(body).lossyUTF8 : text
        return FormattedBody(text: pretty, language: .json, note: note)
    }

    /// Back to compact form, for copying a body into a command line.
    public static func minified(_ text: String, language: BodyLanguage) -> String {
        language == .json ? JSONFormatter.minify(text) : text
    }

    public static func hexDump(_ data: Data, limit: Int = 8192) -> String {
        let bytes = [UInt8](data.prefix(limit))
        var lines: [String] = []
        for start in stride(from: 0, to: bytes.count, by: 16) {
            let row = bytes[start ..< min(start + 16, bytes.count)]
            let hex = row.hexDigits(separator: " ")
            let ascii = String(row.map { (32 ..< 127).contains($0) ? Character(UnicodeScalar($0)) : "." })
            lines.append(String(format: "%08x  ", start) + hex.padding(toLength: 47, withPad: " ", startingAt: 0) + "  " + ascii)
        }
        if data.count > limit {
            lines.append("… \(data.count - limit) more bytes")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    private static func prettyXML(_ data: Data, html: Bool) -> String? {
        #if os(macOS)
            let options: XMLNode.Options = html ? [.documentTidyHTML] : []
            guard let document = try? XMLDocument(data: data, options: options) else { return nil }
            return document.xmlString(options: [.nodePrettyPrint]).trimmingCharacters(in: .whitespacesAndNewlines)
        #else
            return nil
        #endif
    }

    private static func urlEncodedLines(_ text: String) -> String {
        text.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
            return parts.count == 2 ? "\(parts[0]) = \(parts[1])" : parts[0]
        }.joined(separator: "\n")
    }

    private static func plistText(_ data: Data) -> String? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let xml = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0) else { return nil }
        return String(data: xml, encoding: .utf8)
    }
}
