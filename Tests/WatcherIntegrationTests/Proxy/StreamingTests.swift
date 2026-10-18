import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network), .serialized)
struct StreamingTests {
    @Test(.tags(.timing))
    func eventStreamIsRelayedIncrementallyAndCapturedWhole() async throws {
        let origin = StreamOrigin()
        try await origin.start()
        do {
            try await streamThroughTheProxy(from: origin)
        } catch {
            await origin.stop()
            throw error
        }
        await origin.stop()
    }

    private func streamThroughTheProxy(from origin: StreamOrigin) async throws {
        try await withHarness { harness in
            let client = RawClient()
            try await client.connect(port: harness.proxyPort)
            let started = Date()
            try await client.send(
                "GET http://127.0.0.1:\(origin.port)/events HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
            )

            let first = await client.received(containing: "data: one")
            let firstArrival = Date().timeIntervalSince(started)
            #expect(first.contains("data: one") && !first.contains("data: two"), "\(first)")
            #expect(firstArrival < 0.9, "first event must not wait for the stream to finish")

            let all = await client.received(containing: "data: two")
            #expect(all.contains("data: two"), "\(all)")
            await client.close()

            _ = await eventually(poll: .milliseconds(50)) {
                harness.engine.store.all.first?.state == .completed
            }
            let flow = try #require(harness.engine.store.all.first)
            #expect(flow.state == .completed)
            #expect(String(bytes: flow.response?.body ?? Data(), encoding: .utf8) == "data: one\n\ndata: two\n\n")
        }
    }
}
