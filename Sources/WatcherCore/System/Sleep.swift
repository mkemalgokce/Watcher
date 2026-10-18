/// Waits for a duration; injected so tests can check a delay without spending it.
public typealias Sleep = @Sendable (Duration) async throws -> Void

/// The real wait every `Sleep` parameter defaults to.
public let liveSleep: Sleep = { try await Task.sleep(for: $0) }
