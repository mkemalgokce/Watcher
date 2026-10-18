import SwiftUI
import UniformTypeIdentifiers
import WatcherCore

/// The shared read-only table for headers, parameters and cookies: names in the syntax "key" colour, values selectable,
/// each row copyable, with a filter once the list gets long.
struct KeyValueTable: View {
    @Environment(RequestActions.self) private var actions
    let rows: [KeyValueRow]
    var emptyText = "None"
    @State private var filter = ""
    @State private var previewing: FormField?

    private var shown: [KeyValueRow] {
        KeyValueFilter.apply(filter, to: rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if KeyValueFilter.isOffered(forRowCount: rows.count) {
                TextField("Filter \(rows.count) entries", text: $filter).textFieldStyle(.roundedBorder).controlSize(.small)
                    .accessibilityLabel("Filter entries")
            }
            if rows.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            } else if shown.isEmpty {
                Text("No entries match “\(filter)”.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
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
                                    Button("Copy \(row.name)", systemImage: "doc.on.doc") {
                                        actions.copy(row.value, "\(row.name) copied")
                                    }
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
