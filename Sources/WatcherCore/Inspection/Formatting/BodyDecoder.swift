import Compression
import Foundation

/// Undoes `Content-Encoding` so a compressed body can be read.
public enum BodyDecoder {
    public struct Decoded: Sendable {
        public let data: Data
        /// The encoding that was removed, e.g. `gzip`; nil when the body was already plain.
        public let removedEncoding: String?
    }

    private static let maxOutput = 64 * 1024 * 1024

    public static func decode(_ data: Data, contentEncoding: String?) -> Decoded {
        guard let encoding = contentEncoding?.lowercased().split(separator: ",").last?.trimmingCharacters(in: .whitespaces), !data.isEmpty else {
            return Decoded(data: data, removedEncoding: nil)
        }
        let decoded: Data? = switch encoding {
        case "gzip", "x-gzip": gunzip(data)
        case "deflate": inflateZlib(data)
        case "br": decompress(data, algorithm: COMPRESSION_BROTLI)
        default: nil
        }
        return decoded.map { Decoded(data: $0, removedEncoding: encoding) } ?? Decoded(data: data, removedEncoding: nil)
    }

    /// gzip = 10-byte header (+ optional fields), raw deflate, 8-byte trailer.
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { return nil }; offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {
            guard let end = bytes[offset...].firstIndex(of: 0) else { return nil }
            offset = end + 1
        }
        if flags & 0x02 != 0 {
            offset += 2
        }
        guard offset < bytes.count - 8 else { return nil }
        return decompress(Data(bytes[offset ..< (bytes.count - 8)]), algorithm: COMPRESSION_ZLIB)
    }

    /// HTTP "deflate" is normally zlib-wrapped (2-byte header, 4-byte checksum) but some servers send raw deflate.
    static func inflateZlib(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        if bytes.count > 6, bytes[0] & 0x0F == 8, (Int(bytes[0]) << 8 | Int(bytes[1])) % 31 == 0 {
            return decompress(Data(bytes[2 ..< (bytes.count - 4)]), algorithm: COMPRESSION_ZLIB)
        }
        return decompress(data, algorithm: COMPRESSION_ZLIB)
    }

    private static func decompress(_ data: Data, algorithm: compression_algorithm) -> Data? {
        var capacity = min(maxOutput, max(64 * 1024, data.count * 8))
        while true {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = data.withUnsafeBytes { source -> Int in
                guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(&output, capacity, base, data.count, nil, algorithm)
            }
            if written == 0 {
                return nil
            }
            if written < capacity {
                return Data(output[..<written])
            }
            guard capacity < maxOutput else { return nil }
            capacity = min(maxOutput, capacity * 4) // output filled the buffer: it may have been cut off, retry larger
        }
    }
}
