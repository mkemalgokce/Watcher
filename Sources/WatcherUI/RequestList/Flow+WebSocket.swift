import WatcherCore

extension Flow {
    /// A WebSocket exchange: it carried messages, or the server switched protocols.
    var isWebSocket: Bool {
        !webSocketMessages.isEmpty || response?.status == 101
    }
}
