import Testing

public extension Trait where Self == ConditionTrait {
    /// Enables a suite only on a machine with an IPv6 loopback, so it reports skipped, with the reason, elsewhere.
    static var ipv6Loopback: Self {
        .enabled(if: IPv6Loopback.isAvailable, "this machine has no IPv6 loopback address (::1) to listen on")
    }
}
