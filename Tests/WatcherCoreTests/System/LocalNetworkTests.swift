import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct LocalNetworkTests {
    @Test
    func addressesAreRealLANIPv4() {
        let addresses = LocalNetwork.ipv4Addresses()
        #expect(addresses.allSatisfy {
            $0.ip != "127.0.0.1" && !$0.ip.hasPrefix("169.254.") && $0.ip.split(separator: ".").count == 4
        })
    }
}
