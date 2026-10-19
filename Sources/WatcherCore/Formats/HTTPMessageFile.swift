import Foundation

/// Turns a local file into a response: either a raw HTTP message (`HTTP/1.1 200 OK ...`) or a plain body.
enum HTTPMessageFile {
    static func response(from data: Data, fileName: String) -> ResponseRecord {
        guard data.starts(with: Array("HTTP/".utf8)), let parsed = parse(data) else {
            return ResponseRecord(status: 200, headers: [Header("Content-Type", mimeType(for: fileName))], body: data)
        }
        return parsed
    }

    private static func parse(_ data: Data) -> ResponseRecord? {
        let separators = [Data("\r\n\r\n".utf8), Data("\n\n".utf8)]
        guard let range = separators.compactMap({ data.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }),
              let head = String(data: data[..<range.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: .newlines)
        let statusLine = lines.removeFirst().split(separator: " ")
        guard statusLine.count >= 2, let status = Int(statusLine[1]) else { return nil }
        let headers = lines.compactMap { line -> Header? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return Header(String(line[..<colon]), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        return ResponseRecord(status: status, headers: headers, body: data[range.upperBound...])
    }

    private struct FileType {
        let extensions: [String], mime: String, contentType: String, isPrefix: Bool

        init(_ extensions: [String], _ mime: String, _ contentType: String, isPrefix: Bool = false) {
            self.extensions = extensions; self.mime = mime; self.contentType = contentType; self.isPrefix = isPrefix
        }

        func matches(_ type: String) -> Bool {
            isPrefix ? type.hasPrefix(contentType) : type.contains(contentType)
        }
    }

    /// Order matters: the first entry a content type matches wins, so `xhtml` is HTML before it is XML.
    private static let types = [
        FileType(["json"], "application/json", "json"),
        FileType(["html", "htm"], "text/html; charset=utf-8", "html"),
        FileType(["xml"], "application/xml", "xml"),
        FileType(["js"], "application/javascript", "javascript"),
        FileType(["css"], "text/css", "css"),
        FileType(["txt"], "text/plain; charset=utf-8", "text/plain", isPrefix: true),
        FileType(["png"], "image/png", "image/png", isPrefix: true),
        FileType(["jpg", "jpeg"], "image/jpeg", "image/jpeg", isPrefix: true),
        FileType(["gif"], "image/gif", "image/gif", isPrefix: true),
        FileType(["svg"], "image/svg+xml", "image/svg", isPrefix: true),
        FileType(["pdf"], "application/pdf", "pdf"),
    ]

    static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return types.first { $0.extensions.contains(ext) }?.mime ?? "application/octet-stream"
    }

    /// The extension of a file holding a body of this content type, nil when it has none.
    static func fileExtension(for contentType: String?) -> String? {
        let type = (contentType ?? "").lowercased()
        return types.first { $0.matches(type) }?.extensions[0]
    }
}
