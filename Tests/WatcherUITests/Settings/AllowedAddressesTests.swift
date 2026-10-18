import Testing
@testable import WatcherUI

@Suite(.tags(.unit))
struct AllowedAddressesTests {
    @Test(arguments: [
        ("192.168.1.*, 10.0.0.5", ["192.168.1.*", "10.0.0.5"]), ("10.0.0.5,", ["10.0.0.5"]),
        ("  a ,, b  ", ["a", "b"]), ("", []), (" , ", []), ("::1", ["::1"]),
    ])
    func theTextIsSplitAtCommasAndTrimmed(text: String, addresses: [String]) {
        #expect(AllowedAddresses.addresses(in: text) == addresses)
    }

    @Test
    func theAddressesJoinIntoOneLineThatParsesBack() {
        let addresses = ["192.168.1.*", "10.0.0.5"]
        #expect(AllowedAddresses.text(for: addresses) == "192.168.1.*, 10.0.0.5")
        #expect(AllowedAddresses.addresses(in: AllowedAddresses.text(for: addresses)) == addresses)
        #expect(AllowedAddresses.text(for: []) == "")
    }

    @Test(arguments: [
        (0, "Keep at most ∞ requests"), (500, "Keep at most 500 requests"), (100_000, "Keep at most 100000 requests"),
    ])
    func aLimitOfZeroReadsAsInfinity(limit: Int, label: String) {
        #expect(FlowLimitText.label(for: limit) == label)
    }
}
