import WatcherCore

/// The frames the WebSocket tab lists: all of them, or without the keep-alive ping and pong frames.
struct WebSocketMessageList {
    let all: [WebSocketMessage]
    let hidesPingPong: Bool

    var shown: [WebSocketMessage] {
        all.filter { !hidesPingPong || ($0.kind != .ping && $0.kind != .pong) }
    }

    var countText: String {
        "\(shown.count) of \(all.count) messages"
    }

    var emptyText: String {
        all.isEmpty ? "The socket has not sent anything yet." : "Only ping/pong frames so far."
    }
}
