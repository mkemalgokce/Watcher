import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    /// `serve` against a stubbed upstream: no sockets, every outcome of a request.
    @Suite(.timeLimit(.minutes(1)))
    struct Serving {
        /// A fresh one each time: a response body can be read only once.
        private static func answer() -> HTTPClientResponse {
            HTTPClientResponse(
                status: .created,
                headers: [
                    "Content-Type": "text/plain", "Content-Length": "2", "Connection": "keep-alive", "X-Origin": "1",
                ],
                body: .bytes(ByteBuffer(string: "ok"))
            )
        }

        private func server(
            _ upstream: UpstreamStub = UpstreamStub(response: answer),
            tools: [Tool] = [],
            now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
        ) -> ProxyServer {
            let server = ProxyServer(authority: nil, upstream: upstream, now: now)
            server.tools.set(tools)
            return server
        }

        private func buffered(_ response: ProxyServer.ClientResponse) throws -> ResponseRecord {
            guard case let .buffered(record) = response else { throw TestSupportError("the answer was streamed") }
            return record
        }

        @Test
        func aResponseTooLargeToInspectIsAnsweredWithAClearMessage() async throws {
            let upstream = UpstreamStub {
                HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer(string: String(repeating: "x", count: 20))))
            }
            let server = ProxyServer(authority: nil, upstream: upstream, bodyLimit: 8)
            server.tools.set([ToolStub(inspectsResponses: true)])
            let response = try await buffered(server.serve(.fixture(), allowStreaming: false))
            let text = try #require(String(bytes: response.body, encoding: .utf8))
            #expect(response.status == 502)
            #expect(text == "Watcher cannot inspect a response larger than 8 bytes", "\(text)")
            #expect(server.store.all.first?.state == .failed)
            try await server.stop()
        }

        @Test
        func aForwardedRequestIsAnsweredByTheUpstreamWithoutConnectionHeaders() async throws {
            let upstream = UpstreamStub(response: Self.answer)
            let server = server(upstream)
            let response = try await buffered(server.serve(.fixture(), allowStreaming: false))
            #expect(response.status == 201)
            #expect(response.body == Data("ok".utf8))
            #expect(response.headers.value(for: "X-Origin") == "1")
            #expect(response.headers.value(for: "Connection") == nil)
            #expect(response.headers.value(for: "Content-Length") == nil)
            let flow = try #require(server.store.all.first)
            #expect(flow.state == .completed)
            #expect(flow.upstreamHTTPVersion == "HTTP/1.1")
            try await server.stop()
        }

        @Test
        func theUpstreamGetsTheRequestWithoutHopByHopHeaders() async throws {
            let upstream = UpstreamStub(response: Self.answer)
            let server = server(upstream)
            let request = RequestRecord.fixture(
                method: "POST",
                headers: [Header("Proxy-Connection", "keep-alive"), Header("TE", "trailers"), Header("X-App", "a")],
                body: Data("payload".utf8)
            )
            _ = await server.serve(request, allowStreaming: false, timeout: 0)
            let sent = try #require(upstream.sent.first)
            #expect(sent.request.method == .POST)
            #expect(sent.request.url == request.url)
            #expect(sent.request.headers.map(\.name) == ["X-App"])
            #expect(sent.timeout == .seconds(1), "a timeout below one second is raised to one")
            try await server.stop()
        }

        @Test
        func anUnreachableUpstreamIsAnswered502AndTheFlowFails() async throws {
            let server = server(UpstreamStub(failure: CocoaError(.featureUnsupported)))
            let response = try await buffered(server.serve(.fixture(host: "down.example"), allowStreaming: false))
            #expect(response.status == 502)
            let text = String(bytes: response.body, encoding: .utf8) ?? ""
            #expect(text.hasPrefix("Watcher could not reach down.example"))
            let flow = try #require(server.store.all.first)
            #expect(flow.state == .failed)
            #expect(flow.error != nil)
            try await server.stop()
        }

        @Test(arguments: [(false, 1), (true, 0)])
        func aBlockedRequestIsAnswered403AndHiddenOnlyWhenAsked(hidden: Bool, listed: Int) async throws {
            let upstream = UpstreamStub()
            let server = server(upstream, tools: [ToolStub(name: "Block List", decision: .block(hidden: hidden))])
            #expect(try await buffered(server.serve(.fixture(), allowStreaming: false)).status == 403)
            #expect(server.store.all.count == listed)
            #expect(server.store.all.allSatisfy { $0.state == .blocked })
            #expect(upstream.sent.isEmpty)
            try await server.stop()
        }

        @Test
        func aToolAnswerSkipsTheUpstream() async throws {
            let upstream = UpstreamStub()
            let mock = ResponseRecord(status: 200, headers: [], body: Data("mock".utf8))
            let server = server(upstream, tools: [ToolStub(name: "Map Local", decision: .respond(mock))])
            #expect(try await buffered(server.serve(.fixture(), allowStreaming: false)).body == Data("mock".utf8))
            #expect(upstream.sent.isEmpty)
            #expect(server.store.all.first?.appliedTools == ["Map Local"])
            try await server.stop()
        }

        @Test(arguments: [true, false])
        func theMarkerHeaderNamesTheToolsOnlyWhenSwitchedOn(marking: Bool) async throws {
            let stamp = ToolStub(name: "Script", inspectsResponses: true, responseHeader: Header("X-Stamp", "1"))
            let server = server(tools: [stamp])
            var settings = WatcherSettings(); settings.markModifiedTraffic = marking
            server.updatePolicies(settings)
            let response = try await buffered(server.serve(.fixture(), allowStreaming: true))
            #expect(response.headers.value(for: "X-Watcher-Applied") == (marking ? "Script" : nil))
            try await server.stop()
        }

        @Test
        func durationAndTimeToFirstByteComeFromTheClock() async throws {
            let ticks = LockedBox(0.0)
            let server = server(now: {
                ticks.mutate { $0 += 1 }
                return Date(timeIntervalSince1970: ticks.value)
            })
            _ = await server.serve(.fixture(), allowStreaming: false)
            let flow = try #require(server.store.all.first)
            // Ticks: 1 started, 2 sent, 3 first byte, 4 finished.
            #expect(flow.timeToFirstByte == 1)
            #expect(flow.duration == 3)
            try await server.stop()
        }

        @Test
        func aBodyOfUnknownLengthIsStreamedAndRecordedWhenItEnds() async throws {
            let upstream = UpstreamStub(response: {
                HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer(string: "s")))
            })
            let server = server(upstream)
            guard case let .streamed(head, _, complete) = await server.serve(.fixture(), allowStreaming: true) else {
                Issue.record("expected a streamed answer"); return
            }
            #expect(head.status == 200)
            #expect(server.store.all.first?.state == .pending)
            complete(Data("s".utf8), nil)
            #expect(server.store.all.first?.state == .completed)
            #expect(server.store.all.first?.response?.body == Data("s".utf8))
            try await server.stop()
        }

        @Test
        func aStreamThatBreaksFailsTheFlow() async throws {
            let server = server(UpstreamStub(response: { HTTPClientResponse(status: .ok) }))
            guard case let .streamed(_, _, complete) = await server.serve(.fixture(), allowStreaming: true) else {
                Issue.record("expected a streamed answer"); return
            }
            complete(Data(), CocoaError(.fileReadUnknown))
            #expect(server.store.all.first?.state == .failed)
            try await server.stop()
        }

        @Test(arguments: [(false, false), (true, true)])
        func aBodyOfUnknownLengthIsBufferedWhenNotAllowedOrAToolReadsIt(allowed: Bool, inspecting: Bool) async throws {
            let server = server(
                UpstreamStub(response: { HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer(string: "b"))) }),
                tools: [ToolStub(inspectsResponses: inspecting)]
            )
            #expect(try await buffered(server.serve(.fixture(), allowStreaming: allowed)).body == Data("b".utf8))
            try await server.stop()
        }
    }
}
