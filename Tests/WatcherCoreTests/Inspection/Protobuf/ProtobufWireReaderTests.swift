import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ProtobufWireReaderTests {
    @Test
    func splitsAMessageIntoFieldsOfEveryWireType() throws {
        let bytes: [UInt8] = [0x08, 0x96, 0x01, 0x11] + [UInt8](repeating: 0, count: 7) + [0x01]
            + [0x1A, 0x02, 0x68, 0x69, 0x25, 0x2A, 0, 0, 0]
        let entries = try ProtobufWireReader.entries(bytes)
        #expect(entries.map(\.field) == [1, 2, 3, 4])
        #expect(entries.map(\.value) == [.varint(150), .fixed64(1 << 56), .bytes([0x68, 0x69]), .fixed32(42)])
    }

    @Test
    func emptyBytesHaveNoFields() throws {
        #expect(try ProtobufWireReader.entries([]).isEmpty)
    }

    @Test(arguments: [
        ([0x08], "truncated varint"),
        ([0x08] + [UInt8](repeating: 0xFF, count: 10), "varint too long"),
        ([0x00], "bad field number"),
        ([0x09, 0x01], "truncated fixed64"),
        ([0x0D, 0x01], "truncated fixed32"),
        ([0x12, 0x03, 0x01], "truncated bytes"),
        ([0x0B], "unsupported wire type"),
    ] as [([UInt8], String)])
    func malformedDataSaysWhatIsWrong(bytes: [UInt8], reason: String) {
        #expect {
            try ProtobufWireReader.entries(bytes)
        } throws: { error in
            (error as? ProtobufWireReader.Malformed)?.description == reason
        }
    }
}
