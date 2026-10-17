import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ClientProcessTests {
    @Test
    func parsesLsofFieldOutput() {
        let output = "p501\ncCurl Tool\nn127.0.0.1:54321->127.0.0.1:9090\n"
            + "p777\ncwatcher-cli\nn127.0.0.1:9090->127.0.0.1:54321\n"
        #expect(ClientProcess.name(forLocalPort: 54321) { _ in output } == "Curl Tool")
        #expect(ClientProcess.name(forLocalPort: 1111) { _ in output } == nil)
        #expect(ClientProcess.name(forLocalPort: 54321) { _ in nil } == nil)
    }
}
