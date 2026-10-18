import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct AccessControlTests {
    @Test
    func loopbackIsAlwaysAllowedAndOthersOnlyWhenListed() {
        let open = AccessControlSettings().compile()
        #expect(open.allows("192.168.1.50"), "switched off: everyone who can connect is allowed")
        let restricted = AccessControlSettings(isEnabled: true, allowedAddresses: ["192.168.1.*", "10.0.0.7"]).compile()
        #expect(restricted.allows("127.0.0.1") && restricted.allows("::1"))
        #expect(restricted.allows("192.168.1.50") && restricted.allows("10.0.0.7"))
        #expect(!restricted.allows("192.168.2.50"))
        #expect(!restricted.allows("8.8.8.8"))
        #expect(!restricted.allows(nil), "an unknown peer is refused")
        let empty = AccessControlSettings(isEnabled: true).compile()
        #expect(!empty.allows("192.168.1.2"), "an empty list admits only this Mac")
    }

    @Test
    func anUnknownPeerIsRefusedEvenWhenSwitchedOff() {
        #expect(!AccessControlSettings().compile().allows(nil))
    }

    @Test
    func patternsAreCaseInsensitiveGlobs() {
        let control = AccessControlSettings(isEnabled: true, allowedAddresses: ["fe80::*"]).compile()
        #expect(control.allows("FE80::1"))
        #expect(!control.allows("fe81::1"))
    }

    @Test(arguments: ["::ffff:127.0.0.1", "::FFFF:192.168.1.50"])
    func anIPv4PeerOnADualStackListenerIsCheckedAsIPv4(address: String) {
        let control = AccessControlSettings(isEnabled: true, allowedAddresses: ["192.168.1.*"]).compile()
        #expect(control.allows(address))
    }

    @Test
    func aMappedAddressOutsideTheListIsStillRefused() {
        let control = AccessControlSettings(isEnabled: true, allowedAddresses: ["192.168.1.*"]).compile()
        #expect(!control.allows("::ffff:192.168.2.50"))
    }
}
