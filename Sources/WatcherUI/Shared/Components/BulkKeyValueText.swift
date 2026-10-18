import WatcherCore

/// Key-value rows written as text, one per line, for editing them in bulk. A `//` prefix keeps a row switched off.
/// File rows have no text form, so they stay where they were.
enum BulkKeyValueText {
    enum Style {
        /// `Name: value`, or `name=value` when the `=` comes first.
        case headers
        /// `name=value` only, so a field name may hold a colon and a value may hold anything.
        case form

        var example: String {
            self == .form ? "name=value" : "name: value"
        }

        fileprivate var separators: String {
            self == .form ? "=" : ":="
        }
    }

    static func text(for rows: [KeyValue], style: Style = .headers) -> String {
        let separator = style == .form ? "=" : ": "
        return rows.filter { $0.file == nil }
            .map { "\($0.isEnabled ? "" : "// ")\($0.name)\(separator)\($0.value)" }
            .joined(separator: "\n")
    }

    static func parse(_ text: String, style: Style = .headers) -> [KeyValue] {
        text.components(separatedBy: "\n").compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let enabled = !line.hasPrefix("//")
            if !enabled {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty, let separator = line.firstIndex(where: { style.separators.contains($0) }) else {
                return line.isEmpty ? nil : KeyValue(line, "", isEnabled: enabled)
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            return KeyValue(name, value, isEnabled: enabled)
        }
    }

    /// The rows after editing `text`: file rows keep their place, and a text row keeps the identity of the row it
    /// replaces, so the list does not redraw as if everything were new.
    static func apply(_ text: String, to rows: [KeyValue], style: Style = .headers) -> [KeyValue] {
        var parsed = parse(text, style: style)[...]
        var result: [KeyValue] = []
        for row in rows {
            if row.file != nil {
                result.append(row)
            } else if var next = parsed.popFirst() {
                next.id = row.id
                result.append(next)
            }
        }
        return result + parsed
    }
}
