import AsyncHTTPClient
import NIOHTTP1
import Testing
@testable import WatcherCore

@Suite(.tags(.unit))
struct ProxyServerTests {
    @Test(arguments: [100, 204, 304])
    func aStatusThatCannotHaveABodyIsNeverStreamed(status: Int) {
        let response = HTTPClientResponse(status: .init(statusCode: status))
        #expect(!ProxyServer.shouldStream(response))
    }

    @Test
    func aResponseWithoutALengthIsStreamed() {
        #expect(ProxyServer.shouldStream(HTTPClientResponse(status: .ok)))
    }

    @Test
    func anEventStreamIsStreamedWhateverItsLength() {
        let headers: HTTPHeaders = ["Content-Type": "text/event-stream", "Content-Length": "1"]
        #expect(ProxyServer.shouldStream(HTTPClientResponse(status: .ok, headers: headers)))
    }

    @Test(arguments: [(1, false), (ProxyServer.maxBodyBytes, true)])
    func aKnownLengthIsStreamedOnlyWhenLarge(length: Int, streamed: Bool) {
        let response = HTTPClientResponse(status: .ok, headers: ["Content-Length": "\(length)"])
        #expect(ProxyServer.shouldStream(response) == streamed)
    }
}
