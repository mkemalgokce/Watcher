import Foundation

/// Imports Charles Proxy JSON sessions (`.chlsj`). Binary `.chls` / `.chlz` files must be exported as JSON from Charles first.
public enum CharlesSession {
    public enum ImportError: Error { case notJSONSession }

    public static func flows(from data: Data) throws -> [Flow] {
        guard let transactions = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ImportError.notJSONSession }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return transactions.enumerated().compactMap { index, transaction in flow(transaction, sequence: index + 1, formatter: formatter) }
    }

    private static func flow(_ transaction: [String: Any], sequence: Int, formatter: ISO8601DateFormatter) -> Flow? {
        guard let host = transaction["host"] as? String, let method = transaction["method"] as? String else { return nil }
        let scheme = transaction["scheme"] as? String ?? "http"
        // Real Charles files carry `actualPort: -1` (and no `port`) for default ports, so only positive values count.
        let port = [transaction["actualPort"], transaction["port"]].compactMap { $0 as? Int }.first { $0 > 0 } ?? (scheme == "https" ? 443 : 80)
        var path = transaction["path"] as? String ?? "/"
        if let query = transaction["query"] as? String, !query.isEmpty {
            path += "?\(query)"
        }

        let request = transaction["request"] as? [String: Any]
        var flow = Flow(sequence: sequence, request: RequestRecord(
            method: method, scheme: scheme, host: host, port: port, path: path,
            headers: headers(request), body: body(request)
        ))
        flow.startedAt = ((transaction["times"] as? [String: Any])?["start"] as? String).flatMap(formatter.date) ?? Date()
        flow.duration = ((transaction["durations"] as? [String: Any])?["total"] as? Double).map { $0 / 1000 }

        if let response = transaction["response"] as? [String: Any], let status = response["status"] as? Int {
            flow.response = ResponseRecord(status: status, headers: headers(response), body: body(response))
            flow.state = .completed
        } else {
            flow.state = .failed
        }
        return flow
    }

    private static func headers(_ message: [String: Any]?) -> [Header] {
        let list = ((message?["header"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
        return list.compactMap {
            guard let name = $0["name"] as? String, let value = $0["value"] as? String else { return nil }
            return Header(name, value)
        }
    }

    /// Charles stores text bodies in `text` and binary ones base64-encoded in `encoded`.
    private static func body(_ message: [String: Any]?) -> Data {
        let body = message?["body"] as? [String: Any]
        if let encoded = body?["encoded"] as? String, let data = Data(base64Encoded: encoded) {
            return data
        }
        return Data((body?["text"] as? String ?? "").utf8)
    }
}
