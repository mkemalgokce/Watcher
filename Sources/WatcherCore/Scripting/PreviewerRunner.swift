import Foundation

public struct PreviewOutput: Sendable {
    public let name: String
    public let text: String
}

/// Runs the user's previewer scripts for a captured response.
final class PreviewerRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var engines: [String: ScriptEngine] = [:]

    /// One engine per distinct source, kept between calls so scripts are parsed once.
    private func engine(for source: String, log: @escaping @Sendable (String) -> Void) -> ScriptEngine {
        lock.withLock {
            if let existing = engines[source] {
                return existing
            }
            let created = ScriptEngine(source: source, log: log)
            engines[source] = created
            return created
        }
    }

    func run(_ rules: [PreviewerRule], for flow: Flow, log: @escaping @Sendable (String) -> Void) async -> [PreviewOutput] {
        guard let response = flow.response else { return [] }
        let message: [String: Any] = [
            "url": flow.request.url, "status": response.status,
            "headers": ScriptPayload.headerDictionary(response.headers),
            "body": String(data: response.body, encoding: .utf8) ?? NSNull(),
            "bodyBase64": response.body.base64EncodedString(),
        ]
        guard let argument = (try? JSONSerialization.data(withJSONObject: [message])).map({ String(decoding: $0, as: UTF8.self) }) else { return [] }

        var outputs: [PreviewOutput] = []
        for rule in rules where rule.matching.compile().matches(flow.request) {
            do {
                let json = try await engine(for: rule.source, log: log).call("preview", argumentsJSON: argument)
                outputs.append(PreviewOutput(name: rule.name, text: Self.text(fromJSON: json)))
            } catch {
                outputs.append(PreviewOutput(name: rule.name, text: "Previewer failed: \(error)"))
            }
        }
        return outputs
    }

    /// A returned string is shown as is; anything else as pretty JSON.
    private static func text(fromJSON json: String) -> String {
        guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) else { return json }
        if let string = value as? String {
            return string
        }
        if value is NSNull {
            return ""
        }
        let pretty = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        return pretty.map { String(decoding: $0, as: UTF8.self) } ?? json
    }
}
