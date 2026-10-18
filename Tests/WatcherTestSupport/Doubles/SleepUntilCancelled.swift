import WatcherCore

/// A `Sleep` that ends only when its task is cancelled, so a delayed effect such as a notice timing out never happens
/// during a test.
public let sleepUntilCancelled: Sleep = { _ in
    try await Task.sleep(for: .seconds(3600))
}
