import Foundation

/// HTTP Archive 1.2 export/import.
public enum HAR {
    public enum ImportError: Error { case invalidDocument }

    private static var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    public static func export(_ flows: [Flow]) throws -> Data {
        let formatter = dateFormatter
        let document: [String: Any] = ["log": [
            "version": "1.2",
            "creator": ["name": "Watcher", "version": "0.1.0"],
            "entries": flows.map { entry($0, formatter: formatter) },
        ]]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    public static func flows(from data: Data) throws -> [Flow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let log = root["log"] as? [String: Any],
              let entries = log["entries"] as? [[String: Any]] else { throw ImportError.invalidDocument }
        let formatter = dateFormatter
        return entries.enumerated().compactMap { index, entry in flow(from: entry, sequence: index + 1, formatter: formatter) }
    }

    // MARK: Export

    private static func entry(_ flow: Flow, formatter: ISO8601DateFormatter) -> [String: Any] {
        let request = flow.request
        let components = URLComponents(string: request.url)
        var requestObject: [String: Any] = [
            "method": request.method, "url": request.url, "httpVersion": "HTTP/1.1",
            "headers": request.headers.map { ["name": $0.name, "value": $0.value] },
            "queryString": (components?.queryItems ?? []).map { ["name": $0.name, "value": $0.value ?? ""] },
            "cookies": [], "headersSize": -1, "bodySize": request.body.count,
        ]
        if !request.body.isEmpty {
            requestObject["postData"] = ["mimeType": request.headers.value(for: "content-type") ?? "", "text": text(request.body).text]
        }
        let duration = (flow.duration ?? 0) * 1000
        var entry: [String: Any] = [
            "startedDateTime": formatter.string(from: flow.startedAt), "time": duration,
            "request": requestObject, "cache": [String: Any](),
            "timings": ["send": 0, "wait": (flow.timeToFirstByte ?? flow.duration ?? 0) * 1000, "receive": max(0, duration - (flow.timeToFirstByte ?? 0) * 1000)],
        ]
        if let response = flow.response {
            let body = text(response.body)
            var content: [String: Any] = ["size": response.body.count, "mimeType": response.headers.value(for: "content-type") ?? "", "text": body.text]
            if body.isBase64 {
                content["encoding"] = "base64"
            }
            entry["response"] = [
                "status": response.status, "statusText": HTTPStatus.reason(response.status),
                "httpVersion": flow.upstreamHTTPVersion ?? "HTTP/1.1", "headers": response.headers.map { ["name": $0.name, "value": $0.value] },
                "cookies": [], "content": content, "redirectURL": response.headers.value(for: "location") ?? "",
                "headersSize": -1, "bodySize": response.body.count,
            ]
        } else {
            entry["response"] = [
                "status": 0,
                "statusText": "",
                "httpVersion": "HTTP/1.1",
                "headers": [],
                "cookies": [],
                "content": ["size": 0, "mimeType": ""],
                "redirectURL": "",
                "headersSize": -1,
                "bodySize": 0,
            ]
        }
        return entry
    }

    private static func text(_ data: Data) -> (text: String, isBase64: Bool) {
        String(data: data, encoding: .utf8).map { ($0, false) } ?? (data.base64EncodedString(), true)
    }

    // MARK: Import

    private static func flow(from entry: [String: Any], sequence: Int, formatter: ISO8601DateFormatter) -> Flow? {
        guard let request = entry["request"] as? [String: Any],
              let method = request["method"] as? String,
              let urlString = request["url"] as? String,
              let url = URLComponents(string: urlString), let host = url.host else { return nil }
        let scheme = url.scheme ?? "http"
        let path = (url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath) + (url.percentEncodedQuery.map { "?\($0)" } ?? "")

        var flow = Flow(sequence: sequence, request: RequestRecord(
            method: method, scheme: scheme, host: host, port: url.port ?? (scheme == "https" ? 443 : 80), path: path,
            headers: headers(request["headers"]), body: Data(((request["postData"] as? [String: Any])?["text"] as? String ?? "").utf8)
        ))
        flow.startedAt = (entry["startedDateTime"] as? String).flatMap(formatter.date) ?? Date()
        flow.duration = (entry["time"] as? Double).map { $0 / 1000 }

        if let response = entry["response"] as? [String: Any], let status = response["status"] as? Int, status > 0 {
            let content = response["content"] as? [String: Any]
            let raw = content?["text"] as? String ?? ""
            let body = content?["encoding"] as? String == "base64" ? Data(base64Encoded: raw) ?? Data() : Data(raw.utf8)
            flow.response = ResponseRecord(status: status, headers: headers(response["headers"]), body: body)
            flow.state = .completed
        } else {
            flow.state = .failed
        }
        return flow
    }

    private static func headers(_ value: Any?) -> [Header] {
        (value as? [[String: Any]] ?? []).compactMap {
            guard let name = $0["name"] as? String, let value = $0["value"] as? String else { return nil }
            return Header(name, value)
        }
    }
}
