import Foundation
import JavaScriptCore

/// Evaluates a proxy auto-config (PAC) script to decide which upstream proxy a request uses.
public final class PACEvaluator: @unchecked Sendable {
    public enum Route: Hashable, Sendable {
        case direct
        case http(host: String, port: Int)
        case socks(host: String, port: Int)
    }

    public struct LoadError: Error, CustomStringConvertible { public let description: String }

    private let context = JSContext()!
    private let lock = NSLock()

    // shortcut: no DNS inside PAC scripts (dnsResolve / isInNet always miss), so rules keyed on resolved IPs fall through to later branches.
    private static let prelude = """
    function isPlainHostName(h) { return h.indexOf('.') < 0; }
    function dnsDomainIs(h, d) { return h.length >= d.length && h.substring(h.length - d.length) === d; }
    function localHostOrDomainIs(h, hd) { return h === hd || hd.lastIndexOf(h + '.', 0) === 0; }
    function dnsDomainLevels(h) { return h.split('.').length - 1; }
    function dnsResolve(h) { return null; }
    function isResolvable(h) { return false; }
    function isInNet(ip, pattern, mask) { return false; }
    function myIpAddress() { return '127.0.0.1'; }
    """

    /// `timeLimit` bounds each run of the script, so one that never finishes cannot stall loading or a lookup.
    public init(script: String, timeLimit: Duration = .seconds(1)) throws {
        ExecutionLimit.apply(timeLimit, to: context)
        let shExpMatch: @convention(block) (String, String) -> Bool = { Wildcard($1).matches($0) }
        context.setObject(shExpMatch, forKeyedSubscript: "shExpMatch" as NSString)
        context.evaluateScript(Self.prelude)
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        context.evaluateScript(script)
        if let failure {
            throw LoadError(description: "PAC script error: \(failure)")
        }
        guard context.evaluateScript("typeof FindProxyForURL === 'function'")?.toBool() == true else {
            throw LoadError(description: "PAC script does not define FindProxyForURL")
        }
    }

    public static func load(from location: String) async throws -> PACEvaluator {
        try await load(from: location) { try await URLSession.shared.data(from: $0).0 }
    }

    /// Takes `fetch` with no default: Swift 6.2 miscompiles async function values made in default arguments.
    public static func load(
        from location: String,
        fetch: @Sendable (URL) async throws -> Data
    ) async throws -> PACEvaluator {
        guard let url = URL(string: location), ["http", "https", "file"].contains(url.scheme ?? "") else {
            throw LoadError(description: "PAC location must be an http(s) or file URL")
        }
        let data = try await fetch(url)
        return try PACEvaluator(script: String(decoding: data, as: UTF8.self))
    }

    /// First usable entry of the script's answer (`PROXY a:1; SOCKS b:2; DIRECT`); `.direct` when it cannot be understood.
    public func route(for url: String, host: String) -> Route {
        let answer = lock.withLock { context.objectForKeyedSubscript("FindProxyForURL").call(withArguments: [url, host])?.toString() ?? "DIRECT" }
        for entry in answer.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let parts = entry.split(separator: " ", maxSplits: 1).map(String.init)
            guard let kind = parts.first?.uppercased() else { continue }
            if kind == "DIRECT" {
                return .direct
            }
            guard parts.count == 2, let colon = parts[1].lastIndex(of: ":"), let port = Int(parts[1][parts[1].index(after: colon)...]) else { continue }
            let target = String(parts[1][..<colon])
            if ["PROXY", "HTTP", "HTTPS"].contains(kind) {
                return .http(host: target, port: port)
            }
            if kind.hasPrefix("SOCKS") {
                return .socks(host: target, port: port)
            }
        }
        return .direct
    }
}
