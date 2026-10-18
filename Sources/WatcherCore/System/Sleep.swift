/// Waits for a duration; injected so tests can check a delay without spending it.
public typealias Sleep = @Sendable (Duration) async throws -> Void
