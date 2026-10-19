import Foundation

/// Turns a captured response into a Map Local mock: the body goes to a file you can edit, and a rule serves that file
/// for the same method and path (any query), so the app keeps getting this answer without the server.
public enum MockMaker {
    public struct Mock: Sendable {
        public let rule: MapLocalRule
        public let file: URL
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    public static func make(from flow: Flow, in folder: URL, files: FileAccess = .live) throws -> Mock {
        guard let response = flow.response else { throw Failure(description: "This request has no response to mock yet.") }
        let decoded = BodyDecoder.decode(response.body, contentEncoding: response.headers.value(for: "content-encoding")).data
        let type = response.headers.value(for: "content-type")
        let ext = HTTPMessageFile.fileExtension(for: type)

        // A plain body file is easiest to edit; status codes other than 200, or types an extension cannot express,
        // need the raw message form (status line + headers), which Map Local also understands.
        func mediaType(_ value: String?) -> String? {
            value?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        }
        let plain = response.status == 200 && ext != nil && mediaType(HTTPMessageFile.mimeType(for: "x.\(ext ?? "")")) == mediaType(type)
        let data: Data
        if plain {
            data = decoded
        } else {
            let headers = response.headers.filter { !["content-length", "content-encoding", "transfer-encoding", "connection"].contains($0.name.lowercased()) }
            let head = (["HTTP/1.1 \(response.status) \(HTTPStatus.reason(response.status))"]
                + headers.map { "\($0.name): \($0.value)" }).joined(separator: "\r\n")
            data = Data((head + "\r\n\r\n").utf8) + decoded
        }

        let directory = folder.appendingPathComponent(safe(flow.request.host), isDirectory: true)
        try files.createDirectory(directory)
        let path = flow.request.pathWithoutQuery
        let base = "\(flow.request.method.lowercased())-\(safe(path == "/" ? "root" : path))"
        let named = directory.appendingPathComponent(base).appendingPathExtension((plain ? ext : nil) ?? "txt")
        let file = unique(named, files: files)
        try files.writeAtomically(data, file)

        let pattern = "^(https?://)?" + NSRegularExpression.escapedPattern(for: flow.request.host) + "(:\\d+)?" + NSRegularExpression.escapedPattern(for: path) + "(\\?.*)?$"
        let rule = MapLocalRule(
            name: "Mock \(flow.request.method) \(flow.request.host)\(path)",
            matching: MatchingRule(pattern: pattern, mode: .regex, methods: [flow.request.method.uppercased()]),
            source: .file(file.path)
        )
        return Mock(rule: rule, file: file)
    }

    private static func safe(_ text: String) -> String {
        let cleaned = text.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return String(String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_")).prefix(80))
    }

    private static func unique(_ url: URL, files: FileAccess) -> URL {
        var candidate = url, n = 2
        let ext = url.pathExtension, stem = url.deletingPathExtension().lastPathComponent
        while files.fileExists(candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(stem)-\(n)").appendingPathExtension(ext); n += 1
        }
        return candidate
    }
}
