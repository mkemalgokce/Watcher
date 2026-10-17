import SwiftUI

/// ⌘/ — every keyboard shortcut in one searchable place, and what the colours and symbols mean.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = Page.shortcuts
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    enum Page: String, CaseIterable { case shortcuts = "Keyboard Shortcuts", legend = "Colours & Symbols" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Help page", selection: $page) { ForEach(Page.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                if page == .shortcuts {
                    TextField("Search shortcuts", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        .focused($searchFocused).accessibilityLabel("Search shortcuts")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                switch page {
                case .shortcuts: shortcuts.padding(16)
                case .legend: Legend().padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 420, idealHeight: 560)
        .onAppear { searchFocused = true }
    }

    private var shortcuts: some View {
        let groups = Shortcut.groups.compactMap { group -> (String, [Shortcut])? in
            let items = search.isEmpty ? group.items : group.items.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.keys.contains(search) }
            return items.isEmpty ? nil : (group.title, items)
        }
        return VStack(alignment: .leading, spacing: 18) {
            if groups.isEmpty {
                Text("No shortcut matches “\(search)”.").foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.0) { title, items in
                Card(title) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                        ForEach(items, id: \.title) { item in
                            GridRow {
                                Keycap(keys: item.keys).gridColumnAlignment(.trailing)
                                Text(item.title)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.title): \(Shortcut.spoken(item.keys))")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A shortcut drawn like the keys on the keyboard.
private struct Keycap: View {
    let keys: String
    var body: some View {
        Text(keys).font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .padding(.horizontal, 7).frame(minWidth: 28, minHeight: 22)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
    }
}
