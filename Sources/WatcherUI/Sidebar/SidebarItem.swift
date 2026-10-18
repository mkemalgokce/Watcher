import WatcherCore

/// What the sidebar narrows the list to.
enum SidebarItem: Hashable {
    case all, starred, errors, webSocket
    case app(String), domain(String)
}

/// The badges next to the sidebar's smart groups and its app and domain sections.
struct SidebarCounts: Equatable {
    var starred = 0, errors = 0, webSocket = 0
    var apps: [FlowGroup] = [], domains: [FlowGroup] = []
}
