import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct AccessControlSettingsTests {
    @Test
    func loopbackIsAlwaysAllowedAndOthersOnlyWhenListed() {
        let open = AccessControlSettings()
        #expect(open.allows("192.168.1.50"), "switched off: everyone who can connect is allowed")
        let restricted = AccessControlSettings(isEnabled: true, allowedAddresses: ["192.168.1.*", "10.0.0.7"])
        #expect(restricted.allows("127.0.0.1") && restricted.allows("::1"))
        #expect(restricted.allows("192.168.1.50") && restricted.allows("10.0.0.7"))
        #expect(!restricted.allows("192.168.2.50"))
        #expect(!restricted.allows("8.8.8.8"))
        #expect(!restricted.allows(nil), "an unknown peer is refused")
        #expect(!AccessControlSettings(isEnabled: true).allows("192.168.1.2"), "an empty list admits only this Mac")
    }
}
