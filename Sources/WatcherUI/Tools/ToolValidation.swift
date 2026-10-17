import Foundation
import WatcherCore

/// Mistakes in a tool rule that would make it silently do nothing, worded as what to fix. Shown above the rule's form and
/// as a warning mark in the rule list.
enum ToolValidation {
    static func problems(_ matching: MatchingRule) -> [String] {
        let pattern = matching.pattern.trimmingCharacters(in: .whitespaces)
        if pattern.isEmpty {
            return ["The URL pattern is empty, so the rule matches every request."]
        }
        if matching.mode == .regex, (try? NSRegularExpression(pattern: pattern)) == nil {
            return ["The regular expression does not compile; the rule matches nothing."]
        }
        return []
    }

    static func problems(_ rule: DNSSpoofRule) -> [String] {
        var list: [String] = []
        let host = rule.host.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            list.append("Enter the host name to resolve.")
        } else if host.contains("://") || host.contains("/") || host.contains("*") {
            list.append("Use a bare host name such as api.example.com: no scheme, path or wildcard.")
        }
        if !isIPAddress(rule.address.trimmingCharacters(in: .whitespaces)) {
            list.append("“\(rule.address)” is not an IPv4 or IPv6 address.")
        }
        return list
    }

    /// `proxyPort` is the port Watcher itself listens on; `others` are the rest of the reverse proxies.
    static func problems(_ rule: ReverseProxyRule, proxyPort: Int, others: [ReverseProxyRule]) -> [String] {
        var list: [String] = []
        if rule.localPort == proxyPort {
            list.append("Port \(rule.localPort) is Watcher's own proxy port; pick another local port.")
        }
        if others.contains(where: { $0.isEnabled && $0.localPort == rule.localPort }) {
            list.append("Another reverse proxy already uses port \(rule.localPort).")
        }
        if rule.remoteHost.trimmingCharacters(in: .whitespaces).isEmpty {
            list.append("Enter the server to forward to.")
        }
        return list
    }

    static func problems(_ rule: CustomCertificateRule, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String] {
        var list: [String] = []
        if rule.host.trimmingCharacters(in: .whitespaces).isEmpty {
            list.append("Enter the host the certificate is for.")
        }
        let path = (rule.p12Path as NSString).expandingTildeInPath
        if rule.p12Path.isEmpty {
            list.append("Choose the .p12 file.")
        } else if !fileExists(path) {
            list.append("No file at \(rule.p12Path).")
        }
        return list
    }

    static func isIPAddress(_ text: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }
}
