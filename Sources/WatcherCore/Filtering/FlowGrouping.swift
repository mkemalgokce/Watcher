/// One row of the sidebar: a host or an app with how many flows it holds.
public struct FlowGroup: Equatable, Identifiable, Sendable {
    public let name: String
    public let count: Int
    /// What sort of client an app row is; nil for a domain.
    public let kind: ClientKind?
    /// For an app row: the `.app` folder to take the icon from, when any of its flows knew it.
    public let bundlePath: String?
    /// For an app row: the raw process names behind it, sorted.
    public let processes: [String]
    public init(name: String, count: Int, kind: ClientKind?, bundlePath: String? = nil, processes: [String] = []) {
        self.name = name; self.count = count; self.kind = kind; self.bundlePath = bundlePath; self.processes = processes
    }

    public var id: String {
        name
    }
}

public enum FlowGrouping {
    public static func apps(_ flows: [Flow]) -> [FlowGroup] {
        let clients = flows.compactMap { flow in flow.request.clientApp.map { Client(name: $0, flow.request) } }
        return Dictionary(grouping: clients, by: { Key(name: $0.name, kind: $0.kind) })
            .map { key, members in
                FlowGroup(
                    name: key.name, count: members.count, kind: key.kind,
                    bundlePath: members.lazy.compactMap(\.bundlePath).first,
                    processes: Set(members.compactMap(\.process)).sorted()
                )
            }
            .sorted(by: byCountThenName)
    }

    /// Registrable-ish domain: the last two labels (three for common second-level suffixes like `co.uk`); IPs are kept whole.
    public static func domains(_ flows: [Flow]) -> [FlowGroup] {
        // Hosts repeat far more than they differ, and splitting one into labels costs more than counting it,
        // so the domain is worked out once per distinct host instead of once per request.
        var perHost: [String: Int] = [:]
        for flow in flows {
            perHost[flow.request.host, default: 0] += 1
        }
        var perDomain: [String: Int] = [:]
        for (host, count) in perHost {
            perDomain[domain(of: host), default: 0] += count
        }
        return perDomain
            .map { FlowGroup(name: $0.key, count: $0.value, kind: nil) }
            .sorted(by: byCountThenName)
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

    private static func byCountThenName(_ lhs: FlowGroup, _ rhs: FlowGroup) -> Bool {
        (lhs.count, rhs.name) > (rhs.count, lhs.name)
    }

    private struct Key: Hashable {
        let name: String
        let kind: ClientKind
    }

    private struct Client {
        let name: String
        /// Flows recorded before kinds existed only know the app, so they count as apps.
        let kind: ClientKind
        let process: String?
        let bundlePath: String?

        init(name: String, _ request: RequestRecord) {
            self.name = name; kind = request.clientKind ?? .app
            process = request.clientProcess; bundlePath = request.clientBundlePath
        }
    }
}
