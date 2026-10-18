import Foundation
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
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(first).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(bound == 0)
        #expect(PortFinder.firstAvailable() != first)
    }
}
