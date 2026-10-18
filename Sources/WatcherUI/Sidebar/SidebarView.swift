import SwiftUI
import WatcherCore

/// Source-list sidebar like Mail's mailboxes: smart groups first, then the apps and domains seen so far.
struct SidebarView: View {
    @Environment(FlowListViewModel.self) private var list
    @Environment(RequestActions.self) private var actions

    var body: some View {
        let counts = list.counts
        List(selection: Bindable(list).sidebar) {
            Section("Requests") {
                row("All Requests", symbol: "tray.full", count: list.flows.count, tag: .all)
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
                            .badge(group.count).tag(SidebarItem.app(group.name)).help(group.name)
                    }
                }
            }
            if !counts.domains.isEmpty {
                Section("Domains") {
                    ForEach(counts.domains) { group in
                        Label { Text(group.name).lineLimit(1).truncationMode(.middle) } icon: { SiteIconView(domain: group.name) }
                            .badge(group.count).tag(SidebarItem.domain(group.name))
                            .contextMenu {
                                Button("Block \(group.name)", systemImage: "nosign") { actions.blockDomain(group.name) }
                                Button("Copy Domain", systemImage: "doc.on.doc") {
                                    actions.copy(group.name, "Domain copied")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .large)
    }

    /// Like Mail's mailboxes: one-colour symbols in the accent tint, and a count only when there is something.
    private func row(_ title: String, symbol: String, count: Int, tag: SidebarItem) -> some View {
        Label(title, systemImage: symbol)
            .badge(count)
            .tag(tag)
    }
}
