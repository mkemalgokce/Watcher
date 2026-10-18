import Testing
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct PortRangeTests {
    @Test(arguments: [(-1, false), (0, false), (1, true), (9090, true), (65535, true), (65536, false)])
    func onlyPortsASocketCanListenOnAreValid(port: Int, isValid: Bool) {
        #expect(PortRange.isValid(port) == isValid)
    }
}
