import Foundation

/// Server-Sent Events (`text/event-stream`) split into events, as the browser's EventSource would see them.
public enum EventStream {
    public struct Event: Equatable, Sendable {
        public var id: String?
        public var event: String?
        public var data: String
        public var retry: Int?
    }

    public static func parse(_ text: String) -> [Event] {
        var events: [Event] = []
        var current = Event(data: ""), hasData = false, lines: [String] = []
        func flush() {
            if hasData || current.event != nil || current.id != nil {
                current.data = lines.joined(separator: "\n"); events.append(current)
            }
            current = Event(data: ""); hasData = false; lines = []
        }
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty {
                flush(); continue
            }
            if line.hasPrefix(":") {
                continue
            } // comment / keep-alive
            let field: String, value: String
            if let colon = line.firstIndex(of: ":") {
                field = String(line[..<colon])
                var rest = line[line.index(after: colon)...]
                if rest.first == " " {
                    rest = rest.dropFirst()
                }
                value = String(rest)
            } else {
                field = line; value = ""
            }
            switch field {
            case "data": lines.append(value); hasData = true
            case "event": current.event = value
            case "id": current.id = value
            case "retry": current.retry = Int(value)
            default: break
            }
        }
        flush()
        return events
    }
}
