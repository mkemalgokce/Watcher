import Foundation

/// Session as a spreadsheet-friendly CSV.
public enum CSVExporter {
    public static func export(_ flows: [Flow]) -> Data {
        let header = ["#", "Method", "URL", "Status", "Duration (ms)", "Request bytes", "Response bytes", "Content-Type", "Tools", "Client app"]
        let rows = flows.map { flow in
            [
                String(flow.sequence),
                flow.request.method,
                flow.request.url,
                flow.response.map { String($0.status) } ?? "",
                flow.duration.map { String(Int($0 * 1000)) } ?? "",
                String(flow.request.body.count),
                String(flow.response?.body.count ?? 0),
                flow.response?.headers.value(for: "content-type") ?? "",
                flow.appliedTools.joined(separator: "; "),
                flow.request.clientApp ?? "",
            ]
        }
        return Data(([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n").utf8) + Data("\r\n".utf8)
    }

    /// RFC 4180 quoting, plus a leading apostrophe on cells a spreadsheet would run as a formula.
    private static func escape(_ cell: String) -> String {
        var value = cell
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        guard value.contains(where: { ",\"\r\n".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
