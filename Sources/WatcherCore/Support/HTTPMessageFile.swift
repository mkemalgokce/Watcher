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

    static func mimeType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "json": "application/json"
        case "html", "htm": "text/html; charset=utf-8"
        case "txt": "text/plain; charset=utf-8"
        case "xml": "application/xml"
        case "js": "application/javascript"
        case "css": "text/css"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "pdf": "application/pdf"
        default: "application/octet-stream"
        }
    }
}
