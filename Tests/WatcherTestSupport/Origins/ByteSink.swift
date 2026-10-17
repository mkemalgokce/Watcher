import Foundation
import NIO

/// Collects every inbound byte; read from the test while the event loop keeps writing.
final class ByteSink: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let lock = NSLock()
    private var data = Data()

    var text: String {
        // swiftlint:disable:next optional_data_string_conversion
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }

    var raw: [UInt8] {
        lock.withLock { Array(data) }
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        lock.withLock { self.data.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? []) }
    }
}
