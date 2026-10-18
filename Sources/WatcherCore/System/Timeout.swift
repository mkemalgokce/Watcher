import Foundation

/// `work` gave no answer within the limit.
struct TimedOut: Error, CustomStringConvertible {
    let what: String
    let limit: Duration
    var description: String {
        "\(what) did not answer within \(limit.formatted())"
    }
}

/// Runs `work`, cancelling it and throwing `TimedOut` if it has not finished within `limit`.
/// `work` must honour cancellation: the group still waits for it to end.
func withTimeout<T: Sendable>(
    _ limit: Duration,
    _ what: String,
    sleep: @escaping Sleep,
    _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await sleep(limit)
            throw TimedOut(what: what, limit: limit)
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw CancellationError() }
        return first
    }
}
