import WatcherCore

/// One row of a read-only name/value list (headers, query parameters, form fields, cookies).
struct KeyValueRow: Identifiable {
    /// The row's position, so it keeps its identity (and the table its scroll position) when the list is redrawn.
    let id: Int
    let name: String
    let value: String
    /// Small symbol in front of the name, e.g. where a parameter came from.
    var symbol: String?
    var symbolHelp: String?
    /// Extra content shown after the value, e.g. a file preview button.
    var file: FormField?
    /// A short warning shown under the value.
    var warning: String?

    /// The value is a JSON object or array, which can be opened in the JSON viewer.
    var isJSON: Bool {
        JSONTree.isDocument(value)
    }
}

extension KeyValueRow {
    static func headers(_ headers: [Header]) -> [KeyValueRow] {
        headers.enumerated().map { KeyValueRow(id: $0, name: $1.name, value: $1.value) }
    }

    static func fields(_ fields: [FormField]) -> [KeyValueRow] {
        fields.enumerated().map { index, field in
            let (symbol, help) = switch field.source {
            case .query: ("questionmark.circle", "Query parameter")
            case .form: ("list.bullet.rectangle", "Form field")
            case .multipart: ("paperclip", "Multipart part")
            }
            return KeyValueRow(
                id: index, name: field.name, value: field.value, symbol: symbol, symbolHelp: help,
                file: field.filename != nil ? field : nil
            )
        }
    }

    static func cookies(_ cookies: [CookieEntry], secureConnection: Bool) -> [KeyValueRow] {
        cookies.enumerated().map { index, cookie in
            var warnings: [String] = []
            if cookie.source == .response {
                if secureConnection, !cookie.isSecure {
                    warnings.append("Not marked Secure")
                }
                if !cookie.isHttpOnly {
                    warnings.append("Readable by scripts (no HttpOnly)")
                }
            }
            let attributes = cookie.attributes.isEmpty ? "" : "  ·  " + cookie.attributes.joined(separator: "; ")
            return KeyValueRow(
                id: index,
                name: cookie.name,
                value: cookie.value + attributes,
                symbol: cookie.source == .request ? "arrow.up.circle" : "arrow.down.circle",
                symbolHelp: cookie.source == .request ? "Sent by the client" : "Set by the server",
                warning: warnings.isEmpty ? nil : warnings.joined(separator: " · ")
            )
        }
    }
}

/// The filter above a long table: offered only for long lists, and ignored once the list is short again, so rows
/// are never hidden by a field that is no longer there.
enum KeyValueFilter {
    static let threshold = 8

    static func isOffered(forRowCount count: Int) -> Bool {
        count > threshold
    }

    static func apply(_ filter: String, to rows: [KeyValueRow]) -> [KeyValueRow] {
        guard isOffered(forRowCount: rows.count), !filter.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(filter) || $0.value.localizedCaseInsensitiveContains(filter)
        }
    }
}
