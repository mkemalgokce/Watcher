import WatcherCore

/// What the sidebar narrows the list to.
enum SidebarItem: Hashable {
    case all, starred, errors, webSocket
    case app(String), domain(String)
}

extension FlowGroup {
    /// The row's name, followed by the raw processes behind it when they are named otherwise.
    var tooltip: String {
        let displayed = IconStore.displayName(name, isLegacy: processes.isEmpty)
        let others = processes.filter { $0 != displayed }
        return others.isEmpty ? displayed : "\(displayed): \(others.joined(separator: ", "))"
    }
}

/// The badges next to the sidebar's smart groups and its app and domain sections.
struct SidebarCounts: Equatable {
    var starred = 0, errors = 0, webSocket = 0
    var apps: [FlowGroup] = [], domains: [FlowGroup] = []
}
