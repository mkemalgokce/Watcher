import AppKit
import SwiftUI
import UniformTypeIdentifiers
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

/// The shared read-only table for headers, parameters and cookies: names in the syntax "key" colour, values selectable,
/// each row copyable, with a filter once the list gets long.
struct KeyValueTable: View {
    @Environment(AppModel.self) private var model
    let rows: [KeyValueRow]
    var emptyText = "None"
    @State private var filter = ""
    @State private var previewing: FormField?

    private var shown: [KeyValueRow] {
        filter.isEmpty ? rows : rows.filter { $0.name.localizedCaseInsensitiveContains(filter) || $0.value.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.count > 8 {
                TextField("Filter \(rows.count) entries", text: $filter).textFieldStyle(.roundedBorder).controlSize(.small)
                    .accessibilityLabel("Filter entries")
            }
            if rows.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ScrollView {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
                        ForEach(shown) { row in
                            GridRow {
                                HStack(spacing: 5) {
                                    if let symbol = row.symbol {
                                        Image(systemName: symbol).foregroundStyle(.secondary).font(.caption).help(row.symbolHelp ?? "").accessibilityLabel(row.symbolHelp ?? "")
                                    }
                                    Text(row.name).font(.system(.callout, design: .monospaced).weight(.medium)).foregroundStyle(Color(nsColor: SyntaxTextView.Theme.color(.key)))
                                        .textSelection(.enabled)
                                }
                                .gridColumnAlignment(.leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    if let file = row.file {
                                        Label(file.filename ?? "file", systemImage: "doc").font(.callout)
                                        Text(row.value).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(row.value.isEmpty ? "(empty)" : row.value).font(.system(.callout, design: .monospaced))
                                            .foregroundStyle(row.value.isEmpty ? .tertiary : .primary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    }
                                    if let warning = row.warning {
                                        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Palette.warning)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 2) {
                                    if let file = row.file, let data = file.data {
                                        Button("Preview file", systemImage: "eye") { previewing = row.file }.labelStyle(.iconOnly).buttonStyle(.borderless).help("Preview the file")
                                        OpenWithMenu(data: data, name: file.filename ?? row.name, contentType: file.contentType)
                                            .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize().help("Open the file in another app")
                                    }
                                    Button("Copy \(row.name)", systemImage: "doc.on.doc") { model.copy(row.value, "\(row.name) copied") }
                                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Copy value")
                                }
                            }
                            .padding(.vertical, 4)
                            Divider().gridCellUnsizedAxes(.horizontal)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .popover(item: Binding(get: { previewing.map(FilePreviewItem.init) }, set: {
            if $0 == nil {
                previewing = nil
            }
        })) { item in
            FilePreview(field: item.field).frame(width: 440, height: 360).padding()
        }
    }

    private struct FilePreviewItem: Identifiable { let field: FormField; var id: String {
        field.name + (field.filename ?? "")
    } }
}

struct FilePreview: View {
    let field: FormField

    var body: some View {
        if let data = field.data {
            if field.contentType?.lowercased().hasPrefix("image/") == true || Base64Finder.imageMime(data) != nil {
                ImagePreview(data: data, mime: field.contentType)
            } else if let text = String(data: data.prefix(200_000), encoding: .utf8), !text.contains("\u{0}") {
                SyntaxTextView(text, language: BodyLanguage.detect(contentType: field.contentType, data: data))
            } else {
                SyntaxTextView(BodyFormatter.hexDump(data, limit: 4096), language: .binary, wraps: false)
            }
        }
    }
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

/// The shared editor for headers, query parameters, form fields and multipart parts: one row per entry with an on/off box,
/// add and remove, an optional file per row, suggestions for common names, and a text mode for pasting many at once.
struct KeyValueEditor: View {
    @Binding var rows: [KeyValue]
    var title: String
    var allowsFiles = false
    var suggestions: [String] = []
    @State private var bulk = false
    @State private var bulkText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Text("\(rows.filter(\.isEnabled).count) of \(rows.count) on").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !suggestions.isEmpty {
                    Menu("Add Common") {
                        ForEach(suggestions, id: \.self) { name in Button(name) { rows.append(KeyValue(name, "")) } }
                    }.fixedSize().controlSize(.small)
                }
                Toggle("Bulk Edit", isOn: $bulk).toggleStyle(.button).controlSize(.small)
                    .help("Edit as text, one “name: value” per line")
                    .onChange(of: bulk) { _, on in
                        if on {
                            bulkText = rows.filter { $0.file == nil }.map { "\($0.isEnabled ? "" : "// ")\($0.name): \($0.value)" }.joined(separator: "\n")
                        } else {
                            rows = Self.parse(bulkText) + rows.filter { $0.file != nil }
                        }
                    }
            }
            if bulk {
                SyntaxTextView(text: $bulkText, language: .http, wraps: false).frame(minHeight: 90)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                Text("Lines starting with // are kept but not sent.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach($rows) { $row in
                        HStack(spacing: 6) {
                            Toggle("Send \(row.name)", isOn: $row.isEnabled).toggleStyle(.checkbox).labelsHidden()
                                .help(row.isEnabled ? "Sent" : "Kept but not sent")
                            TextField("Name", text: $row.name).font(.system(.body, design: .monospaced)).frame(minWidth: 120, idealWidth: 160, maxWidth: 220)
                                .accessibilityLabel("Name")
                            if let file = row.file {
                                Label("\(file.filename) · \(Format.bytes(file.data.count))", systemImage: "doc")
                                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                TextField("Value", text: $row.value).font(.system(.body, design: .monospaced)).accessibilityLabel("Value for \(row.name)")
                            }
                            if allowsFiles {
                                Menu {
                                    Button("Text") { row.file = nil }
                                    Button("Choose File…") {
                                        if let file = Self.chooseFile() {
                                            row.file = file
                                        }
                                    }
                                } label: { Image(systemName: row.file == nil ? "textformat" : "doc") }
                                    .menuStyle(.borderlessButton).fixedSize().help("Text value or file").accessibilityLabel("Value type")
                            }
                            Button("Remove \(row.name)", systemImage: "minus.circle") { rows.removeAll { $0.id == row.id } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove")
                        }
                        .opacity(row.isEnabled ? 1 : 0.55)
                    }
                    Button("Add", systemImage: "plus.circle") { rows.append(KeyValue()) }.buttonStyle(.borderless).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// `Name: value` lines (or `name=value` for forms); `//` keeps a row switched off.
    static func parse(_ text: String) -> [KeyValue] {
        text.components(separatedBy: "\n").compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let enabled = !line.hasPrefix("//")
            if !enabled {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            let separator = line.firstIndex(of: ":") ?? line.firstIndex(of: "=")
            guard let separator else { return KeyValue(line, "", isEnabled: enabled) }
            return KeyValue(line[..<separator].trimmingCharacters(in: .whitespaces), line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces), isEnabled: enabled)
        }
    }

    @MainActor static func chooseFile() -> KeyValue.FilePart? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return KeyValue.FilePart(filename: url.lastPathComponent, contentType: type, data: data)
    }

    static let commonHeaders = [
        "Accept",
        "Accept-Encoding",
        "Accept-Language",
        "Authorization",
        "Cache-Control",
        "Content-Type",
        "Cookie",
        "If-None-Match",
        "Origin",
        "Referer",
        "User-Agent",
        "X-Request-ID",
    ]
}
