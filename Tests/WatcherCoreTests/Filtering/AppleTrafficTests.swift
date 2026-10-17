import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct AppleTrafficTests {
    @Test
    func recognisesAppleHostsAndNotLookalikes() {
        #expect(
            AppleTraffic.isApple("api.apple.com") && AppleTraffic.isApple("p25-ckdatabase.icloud.com")
                && AppleTraffic.isApple("apple.com")
        )
        #expect(
            !(AppleTraffic.isApple("example.com") || AppleTraffic.isApple("notapple.com")
                || AppleTraffic.isApple("apple.com.evil.test"))
        )
    }
}
