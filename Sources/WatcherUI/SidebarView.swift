import SwiftUI
import WatcherCore

/// Source-list sidebar like Mail's mailboxes: smart groups first, then the apps and domains seen so far.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let counts = model.counts
        List(selection: $model.sidebar) {
            Section("Requests") {
                row("All Requests", symbol: "tray.full", count: model.flows.count, tag: .all)
                row("Starred", symbol: "star", count: counts.starred, tag: .starred)
                row("Errors", symbol: "exclamationmark.triangle", count: counts.errors, tag: .errors)
                row("WebSocket", symbol: "bubble.left.and.bubble.right", count: counts.webSocket, tag: .webSocket)
            }
            // Sections appear only with content: swapping a placeholder row for real rows made AppKit warn about a
            // reentrant NSTableView delegate operation while traffic arrived.
            if !counts.apps.isEmpty {
                Section("Apps") {
                    ForEach(counts.apps) { group in
                        Label { Text(IconStore.appName(forProcess: group.name)).lineLimit(1) } icon: { AppIconView(process: group.name) }
                            .badge(group.count).tag(AppModel.SidebarItem.app(group.name)).help(group.name)
                    }
                }
            }
            if !counts.domains.isEmpty {
                Section("Domains") {
                    ForEach(counts.domains) { group in
                        Label { Text(group.name).lineLimit(1).truncationMode(.middle) } icon: { SiteIconView(domain: group.name) }
                            .badge(group.count).tag(AppModel.SidebarItem.domain(group.name))
                            .contextMenu {
                                Button("Block \(group.name)", systemImage: "nosign") {
                                    model.settings.blockList.isEnabled = true
                                    model.settings.blockList.rules.append(BlockRule(name: group.name, matching: MatchingRule(pattern: "*\(group.name)/*")))
                                    model.notify("Requests to \(group.name) are now blocked (Tools ▸ Block List)", .success)
                                }
                                Button("Copy Domain", systemImage: "doc.on.doc") { model.copy(group.name, "Domain copied") }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .large)
    }

    /// Like Mail's mailboxes: one-colour symbols in the accent tint, and a count only when there is something.
    private func row(_ title: String, symbol: String, count: Int, tag: AppModel.SidebarItem) -> some View {
        Label(title, systemImage: symbol)
            .badge(count)
            .tag(tag)
    }
}
