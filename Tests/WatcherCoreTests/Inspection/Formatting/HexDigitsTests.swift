import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HexDigitsTests {
    @Test(arguments: [
        ([], "", ""),
        ([0x00, 0x0F, 0xAB, 0xFF], "", "000fabff"),
        ([0x01, 0x02], " ", "01 02"),
    ] as [([UInt8], String, String)])
    func bytesAreWrittenAsLowercasePairs(bytes: [UInt8], separator: String, hex: String) {
        #expect(bytes.hexDigits(separator: separator) == hex)
    }

    @Test
    func theSeparatorDefaultsToNothing() {
        #expect(Data([0xCA, 0x48]).hexDigits() == "ca48")
    }
}
