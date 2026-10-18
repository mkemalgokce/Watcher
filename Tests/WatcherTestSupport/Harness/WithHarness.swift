import WatcherCore

/// Runs `body` against a started harness and awaits its stop on both the success and the throwing path.
public func withHarness<Result>(
    host: String = "upstream.test",
    origin: OriginAuthority? = nil,
    files: FileAccessFake? = nil,
    clientApp: @escaping @Sendable (Int) -> String? = { _ in nil },
    configure: (inout WatcherSettings) -> Void = { _ in },
    isolation _: isolated (any Actor)? = #isolation,
    _ body: (Harness) async throws -> Result
) async throws -> Result {
    let harness = try Harness(host: host, origin: origin, files: files, clientApp: clientApp)
    do {
        try await harness.start(configure: configure)
        let result = try await body(harness)
        await harness.stop()
        return result
    } catch {
        await harness.stop()
        throw error
    }
}
