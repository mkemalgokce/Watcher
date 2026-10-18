import Foundation

/// Runs user JavaScript (`onRequest` / `onResponse`) on matching traffic.
struct ScriptTool: Tool {
    let name = "Scripting"
    var needsRequestBody: Bool {
        entries.contains { $0.engine.definesOnRequest || $0.matcher.readsBody }
    }

    var inspectsResponses: Bool {
        entries.contains { $0.engine.definesOnResponse }
    }

    private struct Entry {
        let matcher: RequestMatcher
        let engine: ScriptEngine
    }

    private let entries: [Entry]
    private let log: @Sendable (String) -> Void
    private let read: @Sendable (URL) throws -> Data

    init(
        rules: [ScriptRule],
        log: @escaping @Sendable (String) -> Void,
        timeout: Duration = .seconds(10),
        read: @escaping @Sendable (URL) throws -> Data = FileAccess.live.read
    ) {
        self.log = log; self.read = read
        entries = rules.map {
            Entry(matcher: $0.matching.compile(), engine: ScriptEngine(source: $0.source, log: log, timeout: timeout))
        }
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        for entry in entries where entry.engine.definesOnRequest && entry.matcher.matches(request) {
            do {
                let payload = try ScriptPayload.encode(request: request)
                let result = try await entry.engine.call("onRequest", argumentsJSON: "[{}, \(ScriptPayload.json(request.url)), \(payload)]")
                try ScriptPayload.apply(requestJSON: result, to: &request)
            } catch {
                log("onRequest failed for \(request.url): \(error)")
            }
        }
        return .forward
    }

    func intercept(response: inout ResponseRecord, for request: RequestRecord) async {
        for entry in entries where entry.engine.definesOnResponse && entry.matcher.matches(request) {
            do {
                let args = try "[{}, \(ScriptPayload.json(request.url)), \(ScriptPayload.encode(request: request)), \(ScriptPayload.encode(response: response))]"
                let result = try await entry.engine.call("onResponse", argumentsJSON: args)
                try ScriptPayload.apply(responseJSON: result, to: &response, read: read)
            } catch {
                log("onResponse failed for \(request.url): \(error)")
            }
        }
    }
}

/// Conversion between records and the plain JS objects scripts see.
/// Only UTF-8 bodies are exposed; binary bodies pass through unchanged.
enum ScriptPayload {
    static func json(_ string: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [string], options: []), encoding: .utf8))
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    static func encode(request: RequestRecord) throws -> String {
        let query = URLComponents(string: request.path)?.queryItems ?? []
        let object: [String: Any] = [
            "method": request.method,
            "headers": headerDictionary(request.headers),
            "queries": Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last }),
            "body": bodyValue(request.body, headers: request.headers),
        ]
        return try string(from: object)
    }

    static func encode(response: ResponseRecord) throws -> String {
        try string(from: [
            "statusCode": response.status,
            "headers": headerDictionary(response.headers),
            "body": bodyValue(response.body, headers: response.headers),
        ])
    }

    static func apply(requestJSON: String, to request: inout RequestRecord) throws {
        guard let object = try dictionary(requestJSON) else { return }
        if let method = object["method"] as? String {
            request.method = method
        }
        if let headers = object["headers"] as? [String: Any] {
            request.headers = merge(headers, into: request.headers)
        }
        if let queries = object["queries"] as? [String: Any],
           var components = URLComponents(string: request.path)
        {
            components.queryItems = queries.keys.sorted().map { URLQueryItem(name: $0, value: "\(queries[$0] ?? "")") }
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
            request.path = components.string ?? request.path
        }
        if let body = encodedBody(object["body"], original: request.body) {
            request.body = body
        }
    }

    static func apply(
        responseJSON: String,
        to response: inout ResponseRecord,
        read: (URL) throws -> Data
    ) throws {
        guard let object = try dictionary(responseJSON) else { return }
        if let status = (object["statusCode"] as? NSNumber)?.intValue {
            response.status = status
        }
        if let headers = object["headers"] as? [String: Any] {
            response.headers = merge(headers, into: response.headers)
        }
        if let body = encodedBody(object["body"], original: response.body) {
            response.body = body
        }
        if let path = object["bodyFilePath"] as? String,
           let data = try? read(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        {
            response.body = data
        }
    }

    // MARK: Helpers

    private static func headerDictionary(_ headers: [Header]) -> [String: String] {
        Dictionary(headers.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    /// Keeps original header order and casing for untouched names; new names are appended.
    private static func merge(_ edited: [String: Any], into original: [Header]) -> [Header] {
        var remaining = edited
        var result: [Header] = []
        for header in original {
            guard let key = remaining.keys.first(where: { $0.caseInsensitiveCompare(header.name) == .orderedSame }) else { continue }
            result.append(Header(header.name, "\(remaining.removeValue(forKey: key) ?? "")"))
        }
        result += remaining.keys.sorted().map { Header($0, "\(remaining[$0] ?? "")") }
        return result
    }

    private static func bodyValue(_ body: Data, headers: [Header]) -> Any {
        guard let text = String(data: body, encoding: .utf8) else { return NSNull() }
        let isJSON = headers.value(for: "content-type")?.lowercased().contains("json") == true
        if isJSON, let parsed = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
            return parsed
        }
        return text
    }

    private static func encodedBody(_ value: Any?, original _: Data) -> Data? {
        switch value {
        case let text as String: Data(text.utf8)
        case let object as [String: Any]: try? JSONSerialization.data(withJSONObject: object)
        case let array as [Any]: try? JSONSerialization.data(withJSONObject: array)
        default: nil
        }
    }

    private static func string(from object: [String: Any]) throws -> String {
        try String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func dictionary(_ json: String) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }
}
