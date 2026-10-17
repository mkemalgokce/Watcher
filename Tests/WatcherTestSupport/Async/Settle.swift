import Foundation

/// Gives the main actor and the main run loop `seconds` to lay out, draw and answer accessibility requests. It must
/// suspend rather than spin the run loop: a test already runs inside the main queue, which a nested run cannot drain.
@MainActor
public func settle(_ seconds: TimeInterval = 0.4) async {
    try? await Task.sleep(for: .seconds(seconds))
}
