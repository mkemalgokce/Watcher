import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProtobufWireTests {
    struct WireTypes {
        @Test(arguments: [
            ([0x09, 0x01, 0, 0, 0, 0, 0, 0, 0x02], "1: 144115188075855873 (fixed64)"),
            ([0x0D, 0x2A, 0, 0, 0], "1: 42 (fixed32)"),
            ([0x12, 0x02, 0xFF, 0x00], "2: 0xff00"),
        ] as [([UInt8], String)])
        func fixedWidthAndBinaryFieldsAreDescribed(bytes: [UInt8], description: String) {
            #expect(ProtobufWire.describe(Data(bytes)) == description)
        }

        @Test(arguments: [
            [0x09, 0x01, 0x02],
            [0x0D, 0x01],
            [0x12, 0x05, 0x01],
            [0x08],
            [0x00, 0x01],
            [0x0B],
            [0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01],
        ] as [[UInt8]])
        func truncatedOrMalformedDataIsNotProtobuf(bytes: [UInt8]) {
            #expect(ProtobufWire.describe(Data(bytes)) == nil)
        }

        @Test
        func emptyDataIsNotProtobuf() {
            #expect(ProtobufWire.describe(Data()) == nil)
        }

        @Test
        func nestingDeeperThanTheLimitIsShownAsBytes() {
            var message: [UInt8] = [0x08, 0x01]
            for _ in 0 ..< 10 {
                message = [0x0A, UInt8(message.count)] + message
            }
            let lines = ProtobufWire.describe(Data(message))?.split(separator: "\n") ?? []
            #expect(lines.filter { $0.hasSuffix("{") }.count == 8)
            #expect(lines.contains { $0.contains(": 0x") })
        }

        @Test
        func longBinaryFieldsAreCutAfterSixtyFourBytes() {
            let description = ProtobufWire.describe(Data([0x12, 70] + [UInt8](repeating: 0xFF, count: 70)))
            #expect(description == "2: 0x" + String(repeating: "ff", count: 64) + "…")
        }
    }
}
