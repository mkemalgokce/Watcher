import WatcherCore

/// Key-value rows written as text, one `Name: value` per line, for editing them in bulk. A `//` prefix keeps a row
/// switched off. File rows have no text form, so they stay where they were.
enum BulkKeyValueText {
    static func text(for rows: [KeyValue]) -> String {
        rows.filter { $0.file == nil }.map { "\($0.isEnabled ? "" : "// ")\($0.name): \($0.value)" }
            .joined(separator: "\n")
    }

    /// `Name: value` or `name=value`, whichever separator comes first, so `next=https://a.com` stays a form field.
    static func parse(_ text: String) -> [KeyValue] {
        text.components(separatedBy: "\n").compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let enabled = !line.hasPrefix("//")
            if !enabled {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty, let separator = line.firstIndex(where: { ":=".contains($0) }) else {
                return line.isEmpty ? nil : KeyValue(line, "", isEnabled: enabled)
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            return KeyValue(name, value, isEnabled: enabled)
        }
    }

    /// The rows after editing `text`: file rows keep their place, and a text row keeps the identity of the row it
    /// replaces, so the list does not redraw as if everything were new.
    static func apply(_ text: String, to rows: [KeyValue]) -> [KeyValue] {
        var parsed = parse(text)[...]
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
