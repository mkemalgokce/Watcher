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
}
