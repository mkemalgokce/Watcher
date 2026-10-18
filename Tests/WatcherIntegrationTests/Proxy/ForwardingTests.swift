import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct ForwardingTests {
    @Test
    func forwardsAndRecordsAFlow() async throws {
        try await withHarness { harness in
            let (status, body) = try await harness.get("/hello")
            #expect(status == 200)
            #expect(body.hasPrefix("GET /hello"), "\(body)")
            #expect(harness.engine.store.all.first?.response?.status == 200)
        }
    }

    @Test(arguments: [
        ("GET", "/empty", 200),
        ("GET", "/nocontent", 204),
        ("GET", "/close", 200),
        ("HEAD", "/head", 200),
        ("GET", "/notmodified", 304),
    ])
    func bodilessResponsesAreRecordedAsCompleted(method: String, path: String, status: Int) async throws {
        try await withHarness { harness in
            let result = try await harness.get(path, method: method)
            #expect(result.status == status); #expect(result.body == "")
            _ = await eventually(timeout: 1, poll: .milliseconds(50)) {
                harness.engine.store.all.first { $0.request.path == path }?.state == .completed
            }
            let flow = try #require(harness.engine.store.all.first { $0.request.path == path })
            #expect(flow.response?.status == status)
            #expect(flow.state == .completed)
        }
    }

    @Test
    func pipelinedRequestsAreAnsweredInTheOrderTheyWereSent() async throws {
        try await withHarness { harness in
            let port = harness.upstream.port
            func request(_ path: String) -> String {
                "GET http://127.0.0.1:\(port)\(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
            }
            let client = RawClient()
            try await client.connect(port: harness.proxyPort)
            try await client.send(request("/slow") + request("/fast"))
            let reply = await client.received(containing: "GET /fast")
            await client.close()
            let slow = try #require(reply.range(of: "GET /slow"), "\(reply)")
            let fast = try #require(reply.range(of: "GET /fast"), "\(reply)")
            #expect(slow.lowerBound < fast.lowerBound)
        }
    }

    @Test
    func aLargeUploadIsStreamedNotBuffered() async throws {
        try await withHarness { harness in
            let size = 9 * 1024 * 1024
            let reply = try await harness.post("/upload", body: Data(repeating: 0x41, count: size))
            #expect(reply.contains("bytes=\(size)"), "\(reply)")
            // A streamed upload is recorded without its body; a buffered one would keep all 9 MB.
            #expect(harness.engine.store.all.first?.request.body.isEmpty == true)
        }
    }

    @Test
    func timingAndUpstreamVersionAreRecordedAndExportedToHAR() async throws {
        try await withHarness { harness in
            _ = try await harness.get("/timing")
            let flow = try #require(harness.engine.store.all.first)
            #expect(flow.upstreamHTTPVersion == "HTTP/1.1")
            let firstByte = try #require(flow.timeToFirstByte)
            #expect(firstByte >= 0 && firstByte <= (flow.duration ?? 0) + 0.001)

            let har = try JSONSerialization.jsonObject(with: HAR.export([flow])) as? [String: Any]
            let entry = try #require((har?["log"] as? [String: Any])?["entries"] as? [[String: Any]]).first
            #expect((entry?["response"] as? [String: Any])?["httpVersion"] as? String == "HTTP/1.1")
            let wait = (entry?["timings"] as? [String: Any])?["wait"] as? Double ?? -1
            #expect(abs(wait - firstByte * 1000) <= 0.5)
        }
    }
}
