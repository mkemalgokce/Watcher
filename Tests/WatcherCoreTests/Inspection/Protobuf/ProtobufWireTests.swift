import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ProtobufWireTests {
    @Test
    func decodesWireFormatAndRejectsGarbage() {
        // field 1 = 150 (varint), field 2 = "hi", field 3 = nested { 1: 7 }
        let message = Data([0x08, 0x96, 0x01, 0x12, 0x02, 0x68, 0x69, 0x1A, 0x02, 0x08, 0x07])
        #expect(ProtobufWire.describe(message) == "1: 150\n2: \"hi\"\n3 {\n  1: 7\n}")
        #expect(ProtobufWire.describe(Data([0xFF, 0xFF, 0xFF])) == nil)
    }

    @Test(arguments: [
        ("application/grpc", 7, 2), ("Application/GRPC+proto", 6, 1), ("application/grpc", 5, 5),
        ("application/protobuf", 7, 7), ("application/json", 7, 7),
    ] as [(String?, Int, Int)] + [(nil, 7, 7)])
    func onlyAGRPCBodyLongerThanItsFrameHeaderLosesFiveBytes(contentType: String?, size: Int, kept: Int) {
        #expect(ProtobufWire.message(in: Data(count: size), contentType: contentType).count == kept)
    }
}
