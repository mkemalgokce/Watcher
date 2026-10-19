import Foundation

/// Human-readable rendering of a message body: JSON, GraphQL, protobuf, text, or a binary placeholder.
public enum BodyPreview {
    public static func text(_ data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "" }
        let type = contentType?.lowercased() ?? ""

        if let graphQL = graphQL(data) {
            return graphQL
        }
        if type.contains("json"), let pretty = prettyJSON(data) {
            return pretty
        }
        if type.contains("protobuf") || type.contains("grpc") {
            if let described = ProtobufWire.describe(ProtobufWire.message(in: data, contentType: type)) {
                return described
            }
        }
        return String(data: data, encoding: .utf8) ?? "<binary, \(data.count) bytes>"
    }

    /// `{query, operationName, variables}` bodies, shown as query text plus variables.
    public static func graphQL(_ data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let query = object["query"] as? String else { return nil }
        var parts = ["# operation: \(object["operationName"] as? String ?? "(anonymous)")", query]
        if let variables = object["variables"], let json = try? JSONSerialization.data(withJSONObject: variables, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: json, encoding: .utf8)
        {
            parts.append("# variables\n\(text)")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}
