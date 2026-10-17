import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WatcherCore

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
