import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct WebSocketFrameParserTests {
    /// One frame: FIN and opcode in the first byte, then the length in the shortest form RFC 6455 allows.
    private func frame(opcode: UInt8, payload: [UInt8], final: Bool = true, mask: [UInt8]? = nil) -> [UInt8] {
        var bytes: [UInt8] = [(final ? 0x80 : 0) | opcode]
        let maskBit: UInt8 = mask == nil ? 0 : 0x80
        switch payload.count {
        case ..<126: bytes.append(maskBit | UInt8(payload.count))
        case ..<65536: bytes += [maskBit | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
        default: bytes += [maskBit | 127] + (0 ..< 8).reversed().map { UInt8((payload.count >> ($0 * 8)) & 0xFF) }
        }
        guard let mask else { return bytes + payload }
        return bytes + mask + payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }
    }

    private func kinds(_ messages: [(kind: WebSocketMessage.Kind, payload: Data, compressed: Bool)]) -> [String] {
        messages.map { "\($0.kind):\(String(bytes: $0.payload, encoding: .utf8) ?? "<\($0.payload.count) bytes>")" }
    }

    @Test
    func aMaskedTextFrameFromTheClientIsUnmasked() {
        var parser = WebSocketFrameParser()
        let messages = parser.feed(frame(opcode: 0x1, payload: Array("hello".utf8), mask: [1, 2, 3, 4]))
        #expect(kinds(messages) == ["text:hello"])
    }

    @Test
    func aFrameSplitAcrossReadsIsDecodedOnceWhole() {
        var parser = WebSocketFrameParser()
        let bytes = frame(opcode: 0x1, payload: Array("split".utf8))
        #expect(parser.feed(Array(bytes.prefix(3))).isEmpty)
        #expect(kinds(parser.feed(Array(bytes.dropFirst(3)))) == ["text:split"])
    }

    @Test(arguments: [200, 70000])
    func extendedLengthsAreRead(count: Int) {
        var parser = WebSocketFrameParser()
        let messages = parser.feed(frame(opcode: 0x2, payload: [UInt8](repeating: 7, count: count)))
        #expect(messages.first?.kind == .binary)
        #expect(messages.first?.payload.count == count)
    }

    @Test
    func continuationFramesJoinIntoOneMessage() {
        var parser = WebSocketFrameParser()
        let bytes = frame(opcode: 0x1, payload: Array("hel".utf8), final: false)
            + frame(opcode: 0x0, payload: Array("lo".utf8))
        #expect(kinds(parser.feed(bytes)) == ["text:hello"])
    }

    @Test
    func controlFramesAreReportedAsTheyCome() {
        var parser = WebSocketFrameParser()
        let bytes = frame(opcode: 0x9, payload: Array("p".utf8)) + frame(opcode: 0xA, payload: [])
            + frame(opcode: 0x8, payload: [0x03, 0xE8])
        #expect(parser.feed(bytes).map(\.kind) == [.ping, .pong, .close])
    }

    @Test
    func theCompressionBitIsPassedOn() {
        var parser = WebSocketFrameParser()
        var bytes = frame(opcode: 0x1, payload: [1])
        bytes[0] |= 0x40
        #expect(parser.feed(bytes).first?.compressed == true)
    }

    @Test
    func aFrameOverSixteenMegabytesStopsDecodingForGood() {
        var parser = WebSocketFrameParser()
        let header: [UInt8] = [0x82, 127] + (0 ..< 8).reversed().map { UInt8(((16 << 20) + 1) >> ($0 * 8) & 0xFF) }
        #expect(parser.feed(header).isEmpty)
        #expect(parser.feed(frame(opcode: 0x1, payload: Array("after".utf8))).isEmpty)
    }
}
