import Foundation

/// The kinds of body a request can be composed with, and how each becomes bytes plus a `Content-Type`.
public enum RequestBodyBuilder {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case none = "None", json = "JSON", text = "Text", form = "Form URL-Encoded", multipart = "Multipart", graphQL = "GraphQL", binary = "File"
        public var id: Self {
            self
        }
    }

    /// `a=1&b=x+y`: the encoding browsers use for HTML forms.
    public static func urlEncoded(_ fields: [KeyValue]) -> Data {
        Data(fields.filter(\.isSendable).map { "\(formEscape($0.name))=\(formEscape($0.value))" }.joined(separator: "&").utf8)
    }

    public static func multipart(_ fields: [KeyValue], boundary: String) -> Data {
        var body = Data()
        func line(_ text: String) {
            body.append(Data((text + "\r\n").utf8))
        }
        for field in fields where field.isSendable {
            line("--\(boundary)")
            if let file = field.file {
                line("Content-Disposition: form-data; name=\"\(quoted(field.name))\"; filename=\"\(quoted(file.filename))\"")
                line("Content-Type: \(file.contentType)")
                line("")
                body.append(file.data); line("")
            } else {
                line("Content-Disposition: form-data; name=\"\(quoted(field.name))\"")
                line("")
                line(field.value)
            }
        }
        line("--\(boundary)--")
        return body
    }

    /// `{"query": …, "variables": {…}}`; variables must be a JSON object or empty.
    public static func graphQL(query: String, variables: String) throws -> Data {
        var object: [String: Any] = ["query": query]
        let trimmed = variables.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
                throw BuildError(description: "GraphQL variables must be a JSON object, for example {\"id\": 1}.")
            }
            object["variables"] = parsed
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public struct BuildError: Error, CustomStringConvertible {
        public let description: String
        public init(description: String) {
            self.description = description
        }
    }

    public static func newBoundary() -> String {
        "WatcherBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
    }

    public static func contentType(for kind: Kind, boundary: String) -> String? {
        switch kind {
        case .none, .binary: nil
        case .json, .graphQL: "application/json"
        case .text: "text/plain; charset=utf-8"
        case .form: "application/x-www-form-urlencoded"
        case .multipart: "multipart/form-data; boundary=\(boundary)"
        }
    }

    /// Picks the editor a captured request's body belongs in.
    public static func kind(forContentType type: String?, body: Data) -> Kind {
        let type = (type ?? "").lowercased()
        if body.isEmpty {
            return .none
        }
        if type.contains("multipart/form-data") {
            return .multipart
        }
        if type.contains("x-www-form-urlencoded") {
            return .form
        }
        if type.contains("json") {
            return .json
        }
        if type.hasPrefix("text/") || String(data: body, encoding: .utf8) != nil {
            return .text
        }
        return .binary
    }

    private static func formEscape(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._*")
        return (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text).replacingOccurrences(of: "%20", with: "+")
    }

    private static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r\n", with: " ")
    }
}
