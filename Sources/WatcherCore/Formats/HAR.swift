import Foundation

/// HTTP Archive 1.2 export/import.
public enum HAR {
    public enum ImportError: Error { case invalidDocument }

    public static func export(_ flows: [Flow]) throws -> Data {
        let formatter = ISO8601DateFormatter.withFractionalSeconds()
        let document: [String: Any] = ["log": [
            "version": "1.2",
            "creator": ["name": "Watcher", "version": "0.1.0"],
            "entries": flows.map { entry($0, formatter: formatter) },
        ]]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    /// `now` stands in for entries without a readable start time.
    public static func flows(from data: Data, now: Date = Date()) throws -> [Flow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let log = root["log"] as? [String: Any],
              let entries = log["entries"] as? [[String: Any]] else { throw ImportError.invalidDocument }
        let formatter = ISO8601DateFormatter.withFractionalSeconds()
        return entries.enumerated().compactMap { index, entry in
            flow(from: entry, sequence: index + 1, formatter: formatter, now: now)
        }
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
            let mimeType = request.headers.value(for: "content-type") ?? ""
            requestObject["postData"] = contentObject(request.body, mimeType: mimeType)
        }
        let duration = (flow.duration ?? 0) * 1000
        var entry: [String: Any] = [
            "startedDateTime": formatter.string(from: flow.startedAt), "time": duration,
            "request": requestObject, "cache": [String: Any](),
            "timings": timings(flow),
        ]
        if let response = flow.response {
            var content = contentObject(response.body, mimeType: response.headers.value(for: "content-type") ?? "")
            content["size"] = response.body.count
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

    /// `wait` and `receive` split `time` at the first byte; without one, all of it counts as waiting.
    private static func timings(_ flow: Flow) -> [String: Double] {
        let duration = (flow.duration ?? 0) * 1000
        guard let firstByte = flow.timeToFirstByte.map({ $0 * 1000 }) else {
            return ["send": 0, "wait": duration, "receive": 0]
        }
        return ["send": 0, "wait": firstByte, "receive": max(0, duration - firstByte)]
    }

    /// HAR 1.2 defines `encoding` for response content only; request bodies use it too so bytes that are not UTF-8 survive.
    private static func contentObject(_ data: Data, mimeType: String) -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8) else {
            return ["mimeType": mimeType, "text": data.base64EncodedString(), "encoding": "base64"]
        }
        return ["mimeType": mimeType, "text": text]
    }

    private static func data(fromContent content: Any?) -> Data {
        let content = content as? [String: Any], text = content?["text"] as? String ?? ""
        return content?["encoding"] as? String == "base64" ? Data(base64Encoded: text) ?? Data() : Data(text.utf8)
    }

    // MARK: Import

    private static func flow(
        from entry: [String: Any],
        sequence: Int,
        formatter: ISO8601DateFormatter,
        now: Date
    ) -> Flow? {
        guard let request = entry["request"] as? [String: Any],
              let method = request["method"] as? String,
              let urlString = request["url"] as? String,
              let url = URLComponents(string: urlString), let host = url.host else { return nil }
        let scheme = url.scheme ?? "http"
        let path = (url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath) + (url.percentEncodedQuery.map { "?\($0)" } ?? "")

        let record = RequestRecord(
            method: method, scheme: scheme, host: HostPort.unbracketed(host),
            port: url.port ?? RequestRecord.defaultPort(for: scheme), path: path,
            headers: [Header](jsonList: request["headers"]),
            body: data(fromContent: request["postData"])
        )
        let startedAt = (entry["startedDateTime"] as? String).flatMap(formatter.date) ?? now
        var flow = Flow(sequence: sequence, request: record, startedAt: startedAt)
        flow.duration = (entry["time"] as? Double).map { $0 / 1000 }

        if let response = entry["response"] as? [String: Any], let status = response["status"] as? Int, status > 0 {
            let body = data(fromContent: response["content"])
            flow.response = ResponseRecord(status: status, headers: [Header](jsonList: response["headers"]), body: body)
            flow.state = .completed
        } else {
            flow.state = .failed
        }
        return flow
    }
}
