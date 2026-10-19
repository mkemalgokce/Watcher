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
            clientSection("Apps", .app)
            clientSection("Tools", .tool)
            clientSection("Devices", .device)
            if !list.groups(of: .service).isEmpty {
                Section("System Services", isExpanded: Bindable(list).expandsSystemServices) {
                    clientRows(.service)
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

    @ViewBuilder
    private func clientSection(_ title: String, _ kind: ClientKind) -> some View {
        if !list.groups(of: kind).isEmpty {
            Section(title) { clientRows(kind) }
        }
    }

    private func clientRows(_ kind: ClientKind) -> some View {
        ForEach(list.groups(of: kind)) { group in
            Label {
                Text(IconStore.displayName(group.name, kind: group.kind)).lineLimit(1)
            } icon: {
                AppIconView(name: group.name, kind: group.kind, bundlePath: group.bundlePath)
            }
            .badge(group.count).tag(SidebarItem.app(group.name)).help(group.tooltip)
        }
    }

    /// Like Mail's mailboxes: one-colour symbols in the accent tint, and a count only when there is something.
    private func row(_ title: String, symbol: String, count: Int, tag: SidebarItem) -> some View {
        Label(title, systemImage: symbol)
            .badge(count)
            .tag(tag)
    }
}
