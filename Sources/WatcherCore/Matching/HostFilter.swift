import Foundation

public struct HostFilter: Sendable {
    public var include: HostList
    public var exclude: HostList

    public init(include: [String] = ["*"], exclude: [String] = []) {
        self.include = HostList(include); self.exclude = HostList(exclude)
    }

    public func allows(_ host: String) -> Bool {
        include.matches(host) && !exclude.matches(host)
    }
}
