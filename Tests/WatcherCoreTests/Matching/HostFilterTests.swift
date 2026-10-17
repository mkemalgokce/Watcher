import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HostFilterTests {
    @Test
    func excludeWins() {
        let filter = HostFilter(include: ["*.example.com"], exclude: ["secure.example.com"])
        #expect(filter.allows("api.example.com"))
        #expect(!filter.allows("secure.example.com"))
    }
}
