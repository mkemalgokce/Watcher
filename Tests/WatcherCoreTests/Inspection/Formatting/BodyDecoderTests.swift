import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct BodyDecoderTests {
    @Test
    func gzipIsDecodedAndIdentityLeftAlone() {
        let raw = Data("hello hello hello hello".utf8)
        let decoded = BodyDecoder.decode(raw.gzipped, contentEncoding: "gzip")
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
        let gzip = raw.gzipped
        try #require(gzip.count > 8 * 1024 * 1024)
        let decoded = BodyDecoder.decode(gzip, contentEncoding: "gzip")
        #expect(decoded.removedEncoding == "gzip")
        #expect(decoded.data == raw)
    }
}
