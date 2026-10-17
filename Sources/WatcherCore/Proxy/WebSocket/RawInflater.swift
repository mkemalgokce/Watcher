import Compression
import Foundation

/// Streaming raw-deflate decoder (RFC 1951) that keeps its window between calls, as permessage-deflate "context takeover" requires.
final class RawInflater {
    private static let maxOutput = 16 * 1024 * 1024
    private let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    private var ready = false

    init() {
        // The initial values are overwritten by compression_stream_init.
        stream.initialize(to: compression_stream(dst_ptr: UnsafeMutablePointer(bitPattern: 1)!, dst_size: 0, src_ptr: UnsafePointer(bitPattern: 1)!, src_size: 0, state: nil))
        ready = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
    }

    deinit {
        if ready {
            compression_stream_destroy(stream)
        }
        stream.deallocate()
    }

    /// Inflates one message (the caller appends the 00 00 FF FF sync-flush tail); nil on corrupt input or output over 16 MB.
    func inflate(_ input: Data) -> Data? {
        guard ready else { return nil }
        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        return input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Data? in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return output }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count
            while true {
                let produced: Int = chunk.withUnsafeMutableBufferPointer { destination in
                    stream.pointee.dst_ptr = destination.baseAddress!
                    stream.pointee.dst_size = destination.count
                    return compression_stream_process(stream, 0) == COMPRESSION_STATUS_ERROR ? -1 : destination.count - stream.pointee.dst_size
                }
                if produced < 0 || output.count + produced > Self.maxOutput {
                    return nil
                }
                output.append(contentsOf: chunk[..<produced])
                // Done once all input is consumed and the output buffer was not the limiting factor.
                if stream.pointee.src_size == 0, produced < chunk.count {
                    return output
                }
            }
        }
    }
}
