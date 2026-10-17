import Foundation

/// Polls `condition` until it holds or `timeout` passes, and returns whether it finally held.
public func eventually(
    timeout: TimeInterval = 5,
    poll: Duration = .milliseconds(20),
    isolation _: isolated (any Actor)? = #isolation,
    _ condition: () -> Bool
) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition(), Date() < end {
        try? await Task.sleep(for: poll)
    }
    return condition()
}
