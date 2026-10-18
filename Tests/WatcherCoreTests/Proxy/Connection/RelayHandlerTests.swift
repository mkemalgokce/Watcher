import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RelayHandlerTests {
    @Test
    func joinedConnectionsPassBytesBothWaysUntouched() throws {
        let loop = EmbeddedEventLoop()
        let client = EmbeddedChannel(loop: loop), upstream = EmbeddedChannel(loop: loop)
        try RelayHandler.join(client, upstream).wait()
        try client.writeInbound(ByteBuffer(string: "from client"))
        try upstream.writeInbound(ByteBuffer(string: "from upstream"))
        #expect(try upstream.readOutbound(as: ByteBuffer.self) == ByteBuffer(string: "from client"))
        #expect(try client.readOutbound(as: ByteBuffer.self) == ByteBuffer(string: "from upstream"))
    }

    @Test
    func oneSideEndingClosesTheOther() throws {
        let loop = EmbeddedEventLoop()
        let client = EmbeddedChannel(loop: loop), upstream = EmbeddedChannel(loop: loop)
        try client.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait()
        try upstream.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 2)).wait()
        try RelayHandler.join(client, upstream).wait()
        try client.close().wait()
        #expect(!upstream.isActive)
    }
}
