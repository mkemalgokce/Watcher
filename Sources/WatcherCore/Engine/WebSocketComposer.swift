import Foundation

public extension WatcherEngine {
    struct WebSocketComposeError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Opens a WebSocket, sends `messages` as text, collects replies for `listenFor` seconds and records everything as one session entry.
    /// shortcut: connects directly (no tools such as Block List or Map Remote apply, and no proxy is involved).
    func composeWebSocket(url: URL, headers: [Header] = [], messages: [String], listenFor seconds: TimeInterval = 3) async throws {
        guard let scheme = url.scheme, ["ws", "wss"].contains(scheme), let host = url.host else {
            throw WebSocketComposeError(description: "URL must start with ws:// or wss://")
        }
        let flow = store.begin(Self.handshake(url: url, scheme: scheme, host: host, headers: headers))
        let started = now()
        var request = URLRequest(url: url)
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        defer { session.invalidateAndCancel() }
        task.resume()
        let record = Self.recorder(into: store, flow: flow.id)

        do {
            for text in messages {
                try await task.send(.string(text))
                record(.clientToServer, .string(text))
            }
            let receiver = Task {
                while !Task.isCancelled, let message = try? await task.receive() {
                    record(.serverToClient, message)
                }
            }
            try await waitWhileListening(.seconds(seconds))
            task.cancel(with: .normalClosure, reason: nil)
            receiver.cancel()
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 101
            store.update(flow.id) {
                $0.response = ResponseRecord(status: status, headers: [Header("Upgrade", "websocket")]); $0.state = .completed
                $0.duration = now().timeIntervalSince(started)
            }
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            store.update(flow.id) {
                $0.state = .failed; $0.error = "\(error)"; $0.duration = now().timeIntervalSince(started)
            }
            throw error
        }
    }

    private static func handshake(url: URL, scheme: String, host: String, headers: [Header]) -> RequestRecord {
        RequestRecord(
            method: "GET",
            scheme: scheme == "wss" ? "https" : "http",
            host: host,
            port: url.port ?? RequestRecord.defaultPort(for: scheme),
            path: (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?\($0)" } ?? ""),
            headers: headers + [Header("Upgrade", "websocket"), Header("Connection", "Upgrade")]
        )
    }

    private static func recorder(
        into store: FlowStore,
        flow: Flow.ID
    ) -> @Sendable (WebSocketMessage.Direction, URLSessionWebSocketTask.Message) -> Void {
        { direction, message in
            let kind: WebSocketMessage.Kind, payload: Data
            switch message {
            case let .string(text): (kind, payload) = (.text, Data(text.utf8))
            case let .data(data): (kind, payload) = (.binary, data)
            @unknown default: return
            }
            store.appendWebSocketMessage(WebSocketMessage(direction: direction, kind: kind, payload: payload), to: flow)
        }
    }
}
