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

/// The shortcut list shown in Help; update it together with the `.keyboardShortcut`s in WatcherCommands.
struct Shortcut {
    let keys: String
    let title: String

    struct Group { let title: String; let items: [Shortcut] }

    static let groups: [Group] = [
        Group(title: "Capture", items: [
            Shortcut(keys: "⌘E", title: "Record or pause (starts and stops the proxy)"),
            Shortcut(keys: "⇧⌘Y", title: "Send this Mac's traffic through Watcher (system proxy)"),
            Shortcut(keys: "⌘K", title: "Clear the session"),
            Shortcut(keys: "⇧⌘D", title: "Set up a phone, simulator or this Mac"),
        ]),
        Group(title: "Find and filter", items: [
            Shortcut(keys: "⌘F", title: "Filter requests"),
            Shortcut(keys: "⌥⌘F", title: "Find in the body"),
            Shortcut(keys: "⌘G", title: "Next match"),
            Shortcut(keys: "⇧⌘G", title: "Previous match"),
            Shortcut(keys: "⇧⌘J", title: "Filter a JSON body with a path or jq"),
            Shortcut(keys: "⇧⌘L", title: "Clear filters"),
            Shortcut(keys: "⌘1 – ⌘4", title: "All requests, Starred, Errors, WebSocket"),
        ]),
        Group(title: "Selected request", items: [
            Shortcut(keys: "⌘R", title: "Repeat"),
            Shortcut(keys: "⌥⌘R", title: "Edit and repeat"),
            Shortcut(keys: "⌘D", title: "Star or unstar"),
            Shortcut(keys: "⇧⌘C", title: "Copy as cURL"),
            Shortcut(keys: "⌥⌘C", title: "Copy URL"),
            Shortcut(keys: "⌥⌘M", title: "Mock this response from a local file"),
            Shortcut(keys: "⇧⌘B", title: "Set as compare base and open Compare"),
            Shortcut(keys: "⌘⌫", title: "Delete"),
        ]),
        Group(title: "Inspector", items: [
            Shortcut(keys: "⌥⌘[", title: "Show the request (narrow inspector)"),
            Shortcut(keys: "⌥⌘]", title: "Show the response (narrow inspector)"),
            Shortcut(keys: "⌃⌘1 – ⌃⌘4", title: "Body as Preview, Pretty, Raw, Hex"),
            Shortcut(keys: "⌥⌘L", title: "Wrap long lines"),
        ]),
        Group(title: "Windows", items: [
            Shortcut(keys: "⌘N", title: "New request (Compose)"),
            Shortcut(keys: "⌥⌘N", title: "New request from the curl command on the clipboard"),
            Shortcut(keys: "⌘B", title: "Breakpoints: paused requests"),
            Shortcut(keys: "⌘T", title: "Tools: Map Local, Block, Scripting…"),
            Shortcut(keys: "⇧⌘U", title: "Converter: Base64, URL, JWT, timestamps"),
            Shortcut(keys: "⌘,", title: "Settings"),
            Shortcut(keys: "⌘/", title: "This help"),
        ]),
        Group(title: "In Compose and Breakpoints", items: [
            Shortcut(keys: "⌘↩", title: "Send, or continue with your edits"),
            Shortcut(keys: "⇧⌘↩", title: "Continue unchanged"),
            Shortcut(keys: "⇧⌘⌫", title: "Abort the paused request"),
            Shortcut(keys: "⎋", title: "Close"),
        ]),
        Group(title: "File", items: [
            Shortcut(keys: "⌘O", title: "Open a session, HAR or Charles file"),
            Shortcut(keys: "⌘S", title: "Save the session"),
            Shortcut(keys: "⇧⌘E", title: "Export HAR"),
        ]),
    ]

    /// "⇧⌘P" read out as "Shift Command P", so VoiceOver does not skip the symbols.
    static func spoken(_ keys: String) -> String {
        let names: [Character: String] = ["⌘": "Command ", "⇧": "Shift ", "⌥": "Option ", "⌃": "Control ", "↩": "Return", "⌫": "Delete", "⎋": "Escape", "–": " to "]
        return keys.map { names[$0] ?? String($0) }.joined()
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
