import Foundation
import WatcherCore

/// The facts under the inspector header, in the order they are shown: timing, sizes, protocol, TLS, start. The comment comes after them
/// (and after the client app, which the view adds).
struct InspectorMeta {
    struct Item: Equatable {
        let symbol: String
        let text: String
        let help: String
    }

    let items: [Item]
    let comment: Item?

    init(_ flow: Flow, timestamp: Timestamp = Timestamp()) {
        var items = Self.timing(of: flow)
        if !flow.request.body.isEmpty {
            let size = Format.bytes(flow.request.body.count)
            items.append(Item(symbol: "arrow.up.circle", text: size, help: "Request body size"))
        }
        if let response = flow.response {
            let size = Format.bytes(response.body.count)
            items.append(Item(symbol: "arrow.down.circle", text: size, help: "Response body size"))
        }
        if let version = flow.upstreamHTTPVersion {
            items.append(Item(symbol: "network", text: version, help: "Protocol used with the server"))
        }
        if let tls = flow.clientTLS {
            items.append(Item(symbol: "lock.fill", text: tls, help: "TLS between the app and Watcher"))
        }
        items.append(Item(
            symbol: "calendar.badge.clock",
            text: timestamp.clock(flow.startedAt),
            help: "Started \(timestamp.abbreviated(flow.startedAt))"
        ))
        comment = flow.comment.map { Item(symbol: "text.bubble", text: $0, help: "Your comment") }
        self.items = items
    }

    private static func timing(of flow: Flow) -> [Item] {
        let timing = TimingBreakdown(flow)
        if timing.isComplete {
            let help = "Total time. \(timing.verdict)"
            let total = Item(symbol: "clock", text: Format.duration(timing.total), help: help)
            var items = [total]
            if flow.timeToFirstByte != nil {
                items.append(Item(
                    symbol: "hourglass", text: "TTFB \(Format.duration(timing.phases[0].seconds))",
                    help: "Waiting for the server: from sending the request to the first byte back"
                ))
                items.append(Item(
                    symbol: "arrow.down.to.line", text: Format.duration(timing.phases[1].seconds),
                    help: "Downloading the rest of the response"
                ))
            }
            return items
        }
        if flow.state == .pending {
            return [Item(symbol: "clock", text: "Waiting…", help: "The response has not finished yet")]
        }
        return []
    }
}
