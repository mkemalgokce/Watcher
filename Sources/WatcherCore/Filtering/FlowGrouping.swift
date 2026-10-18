/// One row of the sidebar: a host or an app with how many flows it holds.
public struct FlowGroup: Equatable, Identifiable, Sendable {
    public let name: String
    public let count: Int
    public var id: String {
        name
    }
}

public enum FlowGrouping {
    public static func apps(_ flows: [Flow]) -> [FlowGroup] {
        group(flows.compactMap(\.request.clientApp))
    }

    /// Registrable-ish domain: the last two labels (three for common second-level suffixes like `co.uk`); IPs are kept whole.
    public static func domains(_ flows: [Flow]) -> [FlowGroup] {
        group(flows.map { domain(of: $0.request.host) })
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

    private static func group(_ names: [String]) -> [FlowGroup] {
        Dictionary(grouping: names, by: { $0 }).map { FlowGroup(name: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }
}
