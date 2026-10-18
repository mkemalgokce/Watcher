import AsyncHTTPClient
import NIO

/// Sends a request on to the origin (directly or through the configured upstream proxy) and returns its answer.
public protocol UpstreamSending: Sendable {
    func execute(
        _ request: HTTPClientRequest,
        for record: RequestRecord,
        timeout: TimeAmount
    ) async throws -> HTTPClientResponse
}
