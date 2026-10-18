import Testing
@testable import WatcherCore
import WatcherTestSupport

/// Probes real ports from 10000 upwards, so it must not race other tests that bind there.
@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network), .serialized)
struct PortFinderTests {
    @Test
    func startsAt10000AndSkipsTakenAndBusyPorts() throws {
        #expect(PortFinder.firstAvailable(avoiding: []).map { $0 >= 10000 } == true)
        let first = try #require(PortFinder.firstAvailable())
        #expect(try #require(PortFinder.firstAvailable(avoiding: [first])) > first)

        // A port that is really listening must be skipped even if no rule uses it.
        let listener = try LoopbackSocket(port: first)
        #expect(listener.port == first)
        #expect(PortFinder.firstAvailable() != first)
        withExtendedLifetime(listener) {}
    }
}
