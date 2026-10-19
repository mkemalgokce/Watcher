import Foundation

/// Answers matching requests from a local file or directory instead of the network.
struct MapLocalTool: Tool {
    let name = "Map Local"
    var needsRequestBody: Bool {
        entries.contains { $0.matcher.readsBody }
    }

    private let entries: [(rule: MapLocalRule, matcher: RequestMatcher)]
    private let read: @Sendable (URL) throws -> Data
    private let sleep: Sleep

    init(
        rules: [MapLocalRule],
        read: @escaping @Sendable (URL) throws -> Data = FileAccess.live.read,
        sleep: @escaping Sleep = liveSleep
    ) {
        entries = rules.map { ($0, $0.matching.compile()) }
        self.read = read; self.sleep = sleep
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        guard let (rule, _) = entries.first(where: { $0.matcher.matches(request) }) else { return .forward }
        if rule.delayMilliseconds > 0 {
            try? await sleep(.milliseconds(rule.delayMilliseconds))
        }

        let fileURL: URL
        switch rule.source {
        case let .file(path):
            fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        case let .directory(path):
            guard let resolved = Self.resolve(request: request, pattern: rule.matching.pattern, directory: path) else {
                return .respond(ProxyServer.message(403, "Watcher Map Local: path escapes the mapped directory"))
            }
            fileURL = resolved
        }
        guard let data = try? read(fileURL) else {
            return .respond(ProxyServer.message(404, "Watcher Map Local: file not found: \(fileURL.path)"))
        }
        return .respond(HTTPMessageFile.response(from: data, fileName: fileURL.lastPathComponent))
    }

    /// Maps the part of the request path after the pattern's static prefix into `directory`; nil if it would leave it.
    static func resolve(request: RequestRecord, pattern: String, directory: String) -> URL? {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        let requestPath = request.pathWithoutQuery

        let withoutScheme = pattern.components(separatedBy: "://").last ?? pattern
        let staticPart = withoutScheme.prefix { $0 != "*" && $0 != "?" }
        let patternPath = staticPart.firstIndex(of: "/").map { String(staticPart[$0...]) } ?? ""

        var relative = requestPath.hasPrefix(patternPath) ? String(requestPath.dropFirst(patternPath.count)) : requestPath
        relative = relative.removingPercentEncoding ?? relative
        if relative.isEmpty || relative.hasSuffix("/") {
            relative += "index.html"
        }

        let target = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        return target.path.hasPrefix(root.path + "/") ? target : nil
    }
}
