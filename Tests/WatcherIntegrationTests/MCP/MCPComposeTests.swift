import AsyncHTTPClient
import Foundation
import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// `create_compose_http` sends through the started proxy, so it listens on a port.
@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct MCPComposeTests {
    @Test
    func composeSendsTheRequestItDescribesAndSkipsMalformedHeaderLines() async throws {
        let created = HTTPClientResponse(status: .created, body: .bytes(ByteBuffer(string: "made")))
        let upstream = UpstreamStub(response: { created })
        let directory = URL(fileURLWithPath: "/fake-home/.watcher")
        let engine = try WatcherEngine(directory: directory, files: FileAccessFake().access) {
            ProxyServer(store: $0, authority: $1, upstream: upstream)
        }
        _ = try await engine.start(port: 0)
        let headers = #"X-A: 1\nnot a header\nX-B:2"#
        let arguments = #"{"method":"post","url":"http://a.test:8080/p?q=1","headers":"\#(headers)","body":"data"}"#
        let params = #"{"name":"create_compose_http","arguments":\#(arguments)}"#
        let line = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":\#(params)}"#
        let reply = await MCPServer(engine: engine).handle(line)
        try await engine.stop()

        let text = try #require(reply)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let content = (object["result"] as? [String: Any])?["content"] as? [[String: Any]]
        #expect(content?.first?["text"] as? String == "HTTP 201\nmade")
        let sent = try #require(upstream.sent.first?.record)
        #expect((sent.method, sent.host, sent.port, sent.path) == ("POST", "a.test", 8080, "/p?q=1"))
        #expect(sent.headers.filter { ["X-A", "X-B"].contains($0.name) }.map(\.value) == ["1", "2"])
        #expect(!sent.headers.contains { $0.name.hasPrefix("not") })
        #expect(sent.body == Data("data".utf8))
    }

    @Test
    func composeStoresAnIPv6LiteralHostWithoutBrackets() async throws {
        let upstream = UpstreamStub(response: { HTTPClientResponse(status: .ok) })
        let directory = URL(fileURLWithPath: "/fake-home/.watcher")
        let engine = try WatcherEngine(directory: directory, files: FileAccessFake().access) {
            ProxyServer(store: $0, authority: $1, upstream: upstream)
        }
        _ = try await engine.start(port: 0)
        let params = #"{"name":"create_compose_http","arguments":{"url":"http://[::1]:8080/p"}}"#
        let line = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":\#(params)}"#
        _ = await MCPServer(engine: engine).handle(line)
        try await engine.stop()

        let sent = try #require(upstream.sent.first?.record)
        #expect((sent.host, sent.port) == ("::1", 8080))
    }
}
