import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct PortFinderTests {
    @Test
    func aPortPastTheRangeFindsNothingInsteadOfTrapping() {
        #expect(PortFinder.firstAvailable(from: 70000, canBind: { _ in true }) == nil)
        #expect(PortFinder.firstAvailable(from: 65536, canBind: { _ in true }) == nil)
    }

    @Test
    func takenAndBusyPortsAreSkipped() {
        let busy: Set = [10001]
        let found = PortFinder.firstAvailable(from: 10000, avoiding: [10000, 10002], canBind: { !busy.contains($0) })
        #expect(found == 10003)
    }

    @Test
    func anExhaustedRangeFindsNothing() {
        #expect(PortFinder.firstAvailable(from: 65534, canBind: { _ in false }) == nil)
        #expect(PortFinder.firstAvailable(from: 65535, canBind: { $0 == 65535 }) == 65535)
    }
}
