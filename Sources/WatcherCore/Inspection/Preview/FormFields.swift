import Foundation

/// One name/value pair of a request: a query parameter, a urlencoded form field or a multipart part.
public struct FormField: Equatable, Sendable {
    public enum Source: String, Sendable { case query, form, multipart }

    public let source: Source
    public let name: String
    /// Text value; for a file part, a short description instead of its bytes.
    public let value: String
    public let filename: String?
    /// Content type and bytes of an uploaded file part, so an image upload can be shown; nil for ordinary fields.
    public let contentType: String?
    public let data: Data?

    public init(source: Source, name: String, value: String, filename: String?, contentType: String? = nil, data: Data? = nil) {
        self.source = source; self.name = name; self.value = value; self.filename = filename; self.contentType = contentType; self.data = data
    }
}

public enum FormFields {
    /// Query string plus, when the body is `application/x-www-form-urlencoded` or `multipart/form-data`, its fields.
    public static func parse(_ request: RequestRecord) -> [FormField] {
        let query = (URLComponents(string: request.path)?.queryItems ?? []).map {
            FormField(source: .query, name: $0.name, value: $0.value ?? "", filename: nil)
        }
        return query + parse(body: request.body, contentType: request.headers.value(for: "content-type"))
    }

    /// The fields of a body alone, by its content type; empty for any other kind of body.
    public static func parse(body: Data, contentType: String?) -> [FormField] {
        let type = contentType ?? ""
        if type.lowercased().contains("application/x-www-form-urlencoded") {
            // Lossy, so a body that is not UTF-8 still lists its fields.
            // swiftlint:disable:next optional_data_string_conversion
            return urlencoded(String(decoding: body, as: UTF8.self))
        } else if type.lowercased().contains("multipart/form-data"), let boundary = boundary(in: type) {
            return multipart(body, boundary: boundary)
        }
        return []
    }

    /// Split by hand: a captured body may hold spaces, raw UTF-8 or a stray `%`, which `URLComponents` traps on.
    private static func urlencoded(_ body: String) -> [FormField] {
        guard !body.isEmpty else { return [] }
        return body.split(separator: "&", omittingEmptySubsequences: false).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let decoded = parts.map { part in
                let spaced = part.replacingOccurrences(of: "+", with: " ")
                return spaced.removingPercentEncoding ?? spaced
            }
            return FormField(source: .form, name: decoded[0], value: decoded.count > 1 ? decoded[1] : "", filename: nil)
        }
    }

    private static func boundary(in contentType: String) -> String? {
        contentType.components(separatedBy: ";").lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasPrefix("boundary=") }.map { $0.dropFirst("boundary=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }

    private static func multipart(_ body: Data, boundary: String) -> [FormField] {
        let delimiter = Data("--\(boundary)".utf8), separator = Data("\r\n\r\n".utf8)
        var fields: [FormField] = []
        var ranges: [Range<Data.Index>] = []
        var search = body.startIndex ..< body.endIndex
        while let found = body.range(of: delimiter, in: search) {
            ranges.append(found); search = found.upperBound ..< body.endIndex
        }

        for (current, next) in zip(ranges, ranges.dropFirst()) {
            let part = body[current.upperBound ..< next.lowerBound]
            guard let split = part.range(of: separator) else { continue }
            let head = String(decoding: part[part.startIndex ..< split.lowerBound], as: UTF8.self)
            var content = part[split.upperBound...]
            if content.suffix(2) == Data("\r\n".utf8) {
                content = content.dropLast(2)
            }
            guard let disposition = head.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-disposition") }),
                  let name = attribute("name", in: disposition) else { continue }
            let filename = attribute("filename", in: disposition)
            let type = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-type") }?.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
            let value = filename != nil ? "\(type ?? "file"), \(content.count) bytes" : String(decoding: content, as: UTF8.self)
            fields.append(FormField(source: .multipart, name: name, value: value, filename: filename, contentType: filename != nil ? type : nil, data: filename != nil ? Data(content) : nil))
        }
        return fields
    }

    private static func attribute(_ key: String, in header: String) -> String? {
        header.components(separatedBy: ";").lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasPrefix("\(key)=") }.map { $0.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }
}
