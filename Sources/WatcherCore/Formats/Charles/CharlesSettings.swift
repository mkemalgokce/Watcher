import Foundation

/// Imports the tool settings (Block List, Allow List, Map Local, Map Remote, Breakpoints, DNS Spoofing, Reverse Proxies) from a Charles Proxy
/// settings file: the `<configuration>` file Charles keeps in `~/Library/Preferences/com.xk72.charles.config`, or a `<charles-export>` profile.
///
/// The structure was verified against Charles Proxy 5.2.2 itself: a candidate file is fed to `charles --headless --config`, whose parser reports
/// `Unsupported nested element` for anything it does not know and rewrites the file in its canonical form on exit. Defaults are not written by
/// Charles: a missing `toolEnabled` means the tool is off, a missing `enabled` on an entry means it is on.
public enum CharlesSettings {
    public struct ImportError: Error, CustomStringConvertible {
        public let description: String
    }

    /// A parsed XML element: tag, text and children.
    private final class Node {
        let name: String
        var text = ""
        var children: [Node] = []
        init(_ name: String) {
            self.name = name
        }

        func descendants(_ name: String) -> [Node] {
            children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
        }

        func child(_ name: String) -> Node? {
            children.first { $0.name == name }
        }

        func value(_ name: String) -> String? {
            child(name).map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private final class Parser: NSObject, XMLParserDelegate {
        let root = Node("root")
        private var stack: [Node] = []
        override init() {
            super.init(); stack = [root]
        }

        func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?, attributes _: [String: String]) {
            let node = Node(name); stack.last?.children.append(node); stack.append(node)
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
            _ = stack.popLast()
        }
    }

    public static func importSettings(from data: Data) throws -> WatcherSettings {
        let parser = Parser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { throw ImportError(description: "Not a readable XML file: \(xml.parserError?.localizedDescription ?? "unknown error")") }
        let root = parser.root

        var settings = WatcherSettings()
        let block = tool("Block List", "blacklist", in: root), allow = tool("Allow List", "whitelist", in: root)
        settings.blockList = RuleSet(isEnabled: block.map(toolEnabled) ?? false, rules: block.map(locations)?.map {
            BlockRule(name: "Charles", isEnabled: $0.enabled, matching: MatchingRule(pattern: $0.pattern))
        } ?? [])
        settings.allowList = RuleSet(isEnabled: allow.map(toolEnabled) ?? false, rules: allow.map(locations)?.map {
            AllowRule(name: "Charles", isEnabled: $0.enabled, matching: MatchingRule(pattern: $0.pattern))
        } ?? [])

        if let local = tool("Map Local", "mapLocal", in: root) {
            settings.mapLocal = RuleSet(isEnabled: toolEnabled(local), rules: local.descendants("mapLocalMapping").compactMap { entry in
                guard let source = entry.child("sourceLocation"), let destination = entry.value("dest") else { return nil }
                var isDirectory: ObjCBool = false
                let isFolder = FileManager.default.fileExists(atPath: (destination as NSString).expandingTildeInPath, isDirectory: &isDirectory) && isDirectory.boolValue
                return MapLocalRule(
                    name: "Charles",
                    isEnabled: itemEnabled(entry),
                    matching: MatchingRule(pattern: pattern(source)),
                    source: isFolder ? .directory(destination) : .file(destination)
                )
            })
        }
        if let remote = tool("Map Remote", "map", in: root) {
            settings.mapRemote = RuleSet(isEnabled: toolEnabled(remote), rules: remote.descendants("mapMapping").compactMap { entry in
                guard let source = entry.child("sourceLocation"), let target = entry.child("destLocation") else { return nil }
                return MapRemoteRule(
                    name: "Charles",
                    isEnabled: itemEnabled(entry),
                    matching: MatchingRule(pattern: pattern(source)),
                    destination: .init(
                        scheme: target.value("protocol"),
                        host: target.value("host"),
                        port: target.value("port").flatMap(Int.init),
                        path: target.value("path"),
                        query: target.value("query")
                    ),
                    preserveHostHeader: entry.value("preserveHostHeader") == "true"
                )
            })
        }
        if let breakpoints = tool("Breakpoints", "breakpoints", in: root) {
            settings.breakpoints = RuleSet(isEnabled: toolEnabled(breakpoints), rules: breakpoints.descendants("breakpoint").compactMap { entry in
                guard let location = entry.child("location") else { return nil }
                return BreakpointRule(
                    name: "Charles",
                    isEnabled: itemEnabled(entry),
                    matching: MatchingRule(pattern: pattern(location), methods: entry.value("method").map { [$0] } ?? []),
                    onRequest: entry.value("request") == "true",
                    onResponse: entry.value("response") == "true"
                )
            })
        }
        if let dns = tool("DNS Spoofing", "dnsSpoofing", in: root) {
            settings.dnsSpoofing = RuleSet(isEnabled: toolEnabled(dns), rules: dns.descendants("dnsSpoof").compactMap { entry in
                guard let host = entry.value("name"), let address = entry.value("address") else { return nil }
                return DNSSpoofRule(isEnabled: itemEnabled(entry), host: host, address: address)
            })
        }
        if let reverse = tool("Reverse Proxies", "reverseProxies", in: root) {
            // This tool has no `toolEnabled`; its entries carry their own `enabled`.
            let entries: [ReverseProxyRule] = reverse.descendants("reverseProxy").compactMap { entry in
                guard let local = entry.value("sourcePort").flatMap(Int.init), let host = entry.value("destHost") else { return nil }
                let port = entry.value("destPort").flatMap(Int.init) ?? 80
                return ReverseProxyRule(
                    name: "Charles",
                    isEnabled: itemEnabled(entry),
                    localPort: local,
                    remoteHost: host,
                    remotePort: port,
                    forceTLS: port == 443,
                    preserveHost: entry.value("preserveHostHeader") == "true"
                )
            }
            settings.reverseProxy = RuleSet(isEnabled: !entries.isEmpty, rules: entries)
        }
        return settings
    }

    // MARK: Helpers

    /// The value element of the `<entry><string>Title</string><value/></entry>` pair; plain elements are accepted for hand-written files.
    private static func tool(_ title: String, _ element: String, in root: Node) -> Node? {
        let keyed = root.descendants("entry").first { $0.child("string")?.text.trimmingCharacters(in: .whitespacesAndNewlines) == title }
        if let value = keyed?.children.first(where: { $0.name != "string" }), value.name != "null" {
            return value
        }
        // Outermost only: the Breakpoints and Reverse Proxies tools contain a list with the same name.
        return root.descendants(element).first
    }

    /// Charles leaves `toolEnabled` out when it is false.
    private static func toolEnabled(_ tool: Node) -> Bool {
        tool.value("toolEnabled") == "true"
    }

    /// Charles leaves `enabled` out when it is true.
    private static func itemEnabled(_ entry: Node) -> Bool {
        entry.value("enabled") != "false"
    }

    /// Every `locationMatch` under `locations > locationPatterns`, with its own `enabled` flag.
    private static func locations(in tool: Node) -> [(pattern: String, enabled: Bool)] {
        tool.descendants("locationMatch").compactMap { match in match.child("location").map { (pattern($0), itemEnabled(match)) } }
    }

    /// `protocol://host:port/path?query` as a Watcher URL pattern. Charles always writes the port (`443`), which Watcher URLs omit for the
    /// default of the scheme, so a default port is dropped; missing parts match anything.
    private static func pattern(_ location: Node) -> String {
        let scheme = location.value("protocol"), host = location.value("host") ?? "*"
        var port = location.value("port")
        if let portNumber = port.flatMap(Int.init), (scheme == "https" && portNumber == 443) || (scheme == "http" && portNumber == 80) || (scheme == nil && [80, 443].contains(portNumber)) {
            port = nil
        }
        let path = location.value("path") ?? "*", query = location.value("query").map { "?\($0)" } ?? ""
        return "\(scheme ?? "*")://\(host)\(port.map { ":\($0)" } ?? "")\(path.hasPrefix("/") || path == "*" ? "" : "/")\(path)\(query)"
    }
}
