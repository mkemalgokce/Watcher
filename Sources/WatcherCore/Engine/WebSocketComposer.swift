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
        let port = url.port ?? (scheme == "wss" ? 443 : 80)
        let path = (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?\($0)" } ?? "")
        let flow = store.begin(RequestRecord(
            method: "GET",
            scheme: scheme == "wss" ? "https" : "http",
            host: host,
            port: port,
            path: path,
            headers: headers + [Header("Upgrade", "websocket"), Header("Connection", "Upgrade")]
        ))
        let started = Date()

        var request = URLRequest(url: url)
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        defer { session.invalidateAndCancel() }
        task.resume()

        let store = store
        func record(_ direction: WebSocketMessage.Direction, _ message: URLSessionWebSocketTask.Message) {
            switch message {
            case let .string(text): store.appendWebSocketMessage(WebSocketMessage(direction: direction, kind: .text, payload: Data(text.utf8)), to: flow.id)
            case let .data(data): store.appendWebSocketMessage(WebSocketMessage(direction: direction, kind: .binary, payload: data), to: flow.id)
            @unknown default: break
            }
        }

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
            try await Task.sleep(for: .seconds(seconds))
            task.cancel(with: .normalClosure, reason: nil)
            receiver.cancel()
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 101
            store.update(flow.id) {
                $0.response = ResponseRecord(status: status, headers: [Header("Upgrade", "websocket")]); $0.state = .completed
                $0.duration = Date().timeIntervalSince(started)
            }
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            store.update(flow.id) { $0.state = .failed; $0.error = "\(error)"; $0.duration = Date().timeIntervalSince(started) }
            throw error
        }
    }
}
