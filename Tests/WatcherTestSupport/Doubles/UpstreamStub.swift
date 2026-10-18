import AsyncHTTPClient
import Foundation
import NIO
import WatcherCore

/// Stands in for the network behind the proxy: records each request and answers with `response`, or throws `failure`.
public final class UpstreamStub: UpstreamSending, @unchecked Sendable {
    public struct Sent {
        public let request: HTTPClientRequest
        public let record: RequestRecord
        public let timeout: TimeAmount
    }

    private let lock = NSLock()
    private var recorded: [Sent] = []
    private let response: @Sendable () -> HTTPClientResponse
    private let failure: (any Error)?

    public init(
        response: @escaping @Sendable () -> HTTPClientResponse = { HTTPClientResponse(status: .ok) },
        failure: (any Error)? = nil
    ) {
        self.response = response; self.failure = failure
    }

    public var sent: [Sent] {
        lock.withLock { recorded }
    }

    public func execute(
        _ request: HTTPClientRequest,
        for record: RequestRecord,
        timeout: TimeAmount
    ) async throws -> HTTPClientResponse {
        lock.withLock { recorded.append(Sent(request: request, record: record, timeout: timeout)) }
        if let failure {
            throw failure
        }
        return response()
    }
}
