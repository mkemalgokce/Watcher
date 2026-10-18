import Foundation
import WatcherCore

/// Sending requests and WebSocket messages through the proxy, as Repeat and Compose do.
public protocol RequestSending: AnyObject, Sendable {
    func send(_ request: RequestRecord, followRedirects: Bool) async -> ResponseRecord
    func composeWebSocket(url: URL, headers: [Header], messages: [String]) async throws
}

extension WatcherEngine: RequestSending {
    public func send(_ request: RequestRecord, followRedirects: Bool) async -> ResponseRecord {
        await send(request, followRedirects: followRedirects, timeout: nil)
    }

    public func composeWebSocket(url: URL, headers: [Header], messages: [String]) async throws {
        try await composeWebSocket(url: url, headers: headers, messages: messages, listenFor: 3)
    }
}
