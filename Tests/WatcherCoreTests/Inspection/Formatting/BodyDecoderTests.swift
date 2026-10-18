import Compression
import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct BodyDecoderTests {
    @Test
    func gzipIsDecodedAndIdentityLeftAlone() {
        let raw = Data("hello hello hello hello".utf8)
        var deflated = [UInt8](repeating: 0, count: 256)
        let length = raw.withUnsafeBytes {
            compression_encode_buffer(
                &deflated, 256, $0.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB
            )
        }
        var gzip = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3])
        gzip.append(contentsOf: deflated[..<length]); gzip.append(Data(count: 8))
        let decoded = BodyDecoder.decode(gzip, contentEncoding: "gzip")
        #expect(decoded.data == raw)
        #expect(decoded.removedEncoding == "gzip")
        #expect(BodyDecoder.decode(raw, contentEncoding: "identity").removedEncoding == nil)
    }

    @Test
    func aCompressedBodyLargerThanEightMebibytesIsDecoded() throws {
        var state: UInt64 = 1
        let raw = Data((0 ..< 9 * 1024 * 1024).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        })
        var deflated = [UInt8](repeating: 0, count: raw.count + raw.count / 10)
        let length = raw.withUnsafeBytes {
            compression_encode_buffer(
                &deflated, deflated.count, $0.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB
            )
        }
        try #require(length > 8 * 1024 * 1024)
        var gzip = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3])
        gzip.append(contentsOf: deflated[..<length]); gzip.append(Data(count: 8))
        let decoded = BodyDecoder.decode(gzip, contentEncoding: "gzip")
        #expect(decoded.removedEncoding == "gzip")
        #expect(decoded.data == raw)
    }
}
