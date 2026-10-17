import SwiftUI
import WatcherCore

/// One row of a read-only name/value list (headers, query parameters, form fields, cookies).
struct KeyValueRow: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    /// Small symbol in front of the name, e.g. where a parameter came from.
    var symbol: String?
    var symbolHelp: String?
    /// Extra content shown after the value, e.g. a file preview button.
    var file: FormField?
    /// A short warning shown under the value.
    var warning: String?
}

extension KeyValueRow {
    static func headers(_ headers: [Header]) -> [KeyValueRow] {
        headers.map { KeyValueRow(name: $0.name, value: $0.value) }
    }

    static func fields(_ fields: [FormField]) -> [KeyValueRow] {
        fields.map { field in
            let (symbol, help) = switch field.source {
            case .query: ("questionmark.circle", "Query parameter")
            case .form: ("list.bullet.rectangle", "Form field")
            case .multipart: ("paperclip", "Multipart part")
            }
            return KeyValueRow(name: field.name, value: field.value, symbol: symbol, symbolHelp: help, file: field.filename != nil ? field : nil)
        }
    }

    static func cookies(_ cookies: [CookieEntry], secureConnection: Bool) -> [KeyValueRow] {
        cookies.map { cookie in
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
                name: cookie.name,
                value: cookie.value + attributes,
                symbol: cookie.source == .request ? "arrow.up.circle" : "arrow.down.circle",
                symbolHelp: cookie.source == .request ? "Sent by the client" : "Set by the server",
                warning: warnings.isEmpty ? nil : warnings.joined(separator: " · ")
            )
        }
    }
}
