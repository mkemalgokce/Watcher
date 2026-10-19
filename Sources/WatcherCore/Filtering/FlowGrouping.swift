/// One row of the sidebar: a host or an app with how many flows it holds.
public struct FlowGroup: Equatable, Identifiable, Sendable {
    public let name: String
    public let count: Int
    /// What sort of client an app row is; nil for a domain.
    public let kind: ClientKind?
    public var id: String {
        name
    }
}

public enum FlowGrouping {
    public static func apps(_ flows: [Flow]) -> [FlowGroup] {
        // Flows recorded before kinds existed only know the app, so they count as apps.
        group(flows.compactMap { flow in flow.request.clientApp.map { ($0, flow.request.clientKind ?? .app) } })
    }

    /// Registrable-ish domain: the last two labels (three for common second-level suffixes like `co.uk`); IPs are kept whole.
    public static func domains(_ flows: [Flow]) -> [FlowGroup] {
        group(flows.map { (domain(of: $0.request.host), nil) })
    }

    public static func domainName(_ host: String) -> String {
        domain(of: host)
    }

    static func domain(of host: String) -> String {
        let labels = host.split(separator: ".")
        if labels.count <= 2 || labels.allSatisfy({ Int($0) != nil }) {
            return host
        }
        let secondLevel: Set = ["co", "com", "org", "net", "gov", "edu", "ac"]
        let keep = secondLevel.contains(String(labels[labels.count - 2])) && labels.last!.count == 2 ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    private static func group(_ rows: [(name: String, kind: ClientKind?)]) -> [FlowGroup] {
        Dictionary(grouping: rows, by: { Key(name: $0.name, kind: $0.kind) })
            .map { FlowGroup(name: $0.key.name, count: $0.value.count, kind: $0.key.kind) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    private struct Key: Hashable {
        let name: String
        let kind: ClientKind?
    }
}
