import Foundation

/// Turns a captured response into a Map Local mock: the body goes to a file you can edit, and a rule serves that file
/// for the same method and path (any query), so the app keeps getting this answer without the server.
public enum MockMaker {
    public struct Mock: Sendable {
        public let rule: MapLocalRule
        public let file: URL
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    public static func make(from flow: Flow, in folder: URL) throws -> Mock {
        guard let response = flow.response else { throw Failure(description: "This request has no response to mock yet.") }
        let decoded = BodyDecoder.decode(response.body, contentEncoding: response.headers.value(for: "content-encoding")).data
        let type = response.headers.value(for: "content-type")
        let ext = fileExtension(for: type)

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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = flow.request.path.split(separator: "?").first.map(String.init) ?? "/"
        let base = "\(flow.request.method.lowercased())-\(safe(path == "/" ? "root" : path))"
        let file = unique(directory.appendingPathComponent(base).appendingPathExtension(plain ? ext! : "txt"))
        try data.write(to: file)

        let pattern = "^(https?://)?" + NSRegularExpression.escapedPattern(for: flow.request.host) + "(:\\d+)?" + NSRegularExpression.escapedPattern(for: path) + "(\\?.*)?$"
        let rule = MapLocalRule(
            name: "Mock \(flow.request.method) \(flow.request.host)\(path)",
            matching: MatchingRule(pattern: pattern, mode: .regex, methods: [flow.request.method.uppercased()]),
            source: .file(file.path)
        )
        return Mock(rule: rule, file: file)
    }

    static func fileExtension(for contentType: String?) -> String? {
        let type = (contentType ?? "").lowercased()
        if type.contains("json") {
            return "json"
        }
        if type.contains("html") {
            return "html"
        }
        if type.contains("xml") {
            return "xml"
        }
        if type.contains("javascript") {
            return "js"
        }
        if type.contains("css") {
            return "css"
        }
        if type.hasPrefix("text/plain") {
            return "txt"
        }
        if type.hasPrefix("image/png") {
            return "png"
        }
        if type.hasPrefix("image/jpeg") {
            return "jpg"
        }
        if type.hasPrefix("image/gif") {
            return "gif"
        }
        if type.hasPrefix("image/svg") {
            return "svg"
        }
        if type.contains("pdf") {
            return "pdf"
        }
        return nil
    }

    private static func safe(_ text: String) -> String {
        let cleaned = text.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return String(String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_")).prefix(80))
    }

    private static func unique(_ url: URL) -> URL {
        var candidate = url, n = 2
        let ext = url.pathExtension, stem = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(stem)-\(n)").appendingPathExtension(ext); n += 1
        }
        return candidate
    }
}
