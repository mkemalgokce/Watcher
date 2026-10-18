import Compression
import Foundation

public extension Data {
    /// This data in a minimal gzip wrapper (no name, zero CRC), as a `Content-Encoding: gzip` body would carry it.
    var gzipped: Data {
        let capacity = count + count / 10 + 64 // deflate can grow data that does not compress
        var deflated = [UInt8](repeating: 0, count: capacity)
        let length = withUnsafeBytes { source in
            compression_encode_buffer(
                &deflated, capacity, source.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(deflated),
                count, nil, COMPRESSION_ZLIB
            )
        }
        var gzip = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3])
        gzip.append(contentsOf: deflated[..<length])
        gzip.append(Data(count: 8))
        return gzip
    }
}
