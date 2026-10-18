import Foundation
import WatcherCore
import WatcherUI

/// Answers every request with `status` and records what was sent; WebSocket sessions fail when `webSocketFailure` is set.
public final class RequestSenderSpy: RequestSending, @unchecked Sendable {
    private let lock = NSLock()
    private let status: Int
    private let webSocketFailure: (any Error)?
    private var sentRequests: [RequestRecord] = []
    private var sentMessages: [[String]] = []

    public init(status: Int = 200, webSocketFailure: (any Error)? = nil) {
        self.status = status
        self.webSocketFailure = webSocketFailure
    }

    public var sent: [RequestRecord] {
        lock.withLock { sentRequests }
    }

    public var webSocketMessages: [[String]] {
        lock.withLock { sentMessages }
    }

    public func send(_ request: RequestRecord, followRedirects _: Bool) async -> ResponseRecord {
        lock.withLock { sentRequests.append(request) }
        return ResponseRecord(status: status, headers: [], body: Data())
    }

    public func composeWebSocket(url _: URL, headers _: [Header], messages: [String]) async throws {
        lock.withLock { sentMessages.append(messages) }
        if let webSocketFailure {
            throw webSocketFailure
        }
    }
}
