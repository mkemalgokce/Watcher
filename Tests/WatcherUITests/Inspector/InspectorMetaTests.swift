import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The facts under the inspector header: timing, sizes, protocol, TLS, start time and comment.
@Suite(.tags(.unit))
struct InspectorMetaTests {
    private func texts(_ flow: Flow) -> [String] {
        InspectorMeta(flow).items.map(\.text)
    }

    private func symbols(_ flow: Flow) -> [String] {
        InspectorMeta(flow).items.map(\.symbol)
    }

    @Test
    func aFinishedExchangeShowsTotalTimeFirstByteAndDownload() {
        let flow = Flow.fixture(duration: 0.5, timeToFirstByte: 0.2)
        let items = InspectorMeta(flow).items
        #expect(items.prefix(3).map(\.text) == ["500 ms", "TTFB 200 ms", "300 ms"])
        #expect(items.prefix(3).map(\.symbol) == ["clock", "hourglass", "arrow.down.to.line"])
        #expect(items[0].help.hasPrefix("Total time. "))
    }

    @Test
    func aFinishedExchangeWithoutAFirstByteShowsOnlyTheTotal() {
        #expect(texts(.fixture(duration: 2)).first == "2.00 s")
        #expect(!texts(.fixture(duration: 2)).contains { $0.hasPrefix("TTFB") })
    }

    @Test
    func aPendingExchangeSaysItIsWaiting() {
        let flow = Flow.fixture(response: nil, state: .pending)
        #expect(texts(flow).first == "Waiting…")
    }

    @Test
    func aFailedExchangeWithoutATimeShowsNoTiming() {
        let flow = Flow.fixture(response: nil, state: .failed)
        #expect(!symbols(flow).contains("clock"))
    }

    @Test
    func bodySizesAppearOnlyForBodiesThatExist() {
        let request = RequestRecord.fixture(body: Data(count: 2048))
        let sent = Flow.fixture(request: request, response: .fixture(status: 200, body: Data()))
        #expect(texts(sent).contains(Format.bytes(2048)))
        #expect(symbols(sent).contains("arrow.up.circle"))
        #expect(symbols(sent).contains("arrow.down.circle"), "an empty response body is still a response")
        #expect(!symbols(Flow.fixture(response: nil, state: .failed)).contains("arrow.down.circle"))
        #expect(!symbols(Flow.fixture()).contains("arrow.up.circle"))
    }

    @Test
    func protocolTLSAndCommentAreListedWhenKnown() {
        var flow = Flow.fixture()
        flow.upstreamHTTPVersion = "h2"
        flow.clientTLS = "TLS 1.3"
        flow.comment = "check this"
        let items = InspectorMeta(flow).items
        #expect(items.contains(.init(symbol: "network", text: "h2", help: "Protocol used with the server")))
        #expect(items.contains(.init(symbol: "lock.fill", text: "TLS 1.3", help: "TLS between the app and Watcher")))
        #expect(items.last == .init(symbol: "text.bubble", text: "check this", help: "Your comment"))
        #expect(!symbols(.fixture()).contains("network"))
        #expect(!symbols(.fixture()).contains("lock.fill"))
        #expect(!symbols(.fixture()).contains("text.bubble"))
    }

    @Test
    func theStartTimeIsAlwaysListed() {
        let flow = Flow.fixture()
        let item = InspectorMeta(flow).items.first { $0.symbol == "calendar.badge.clock" }
        #expect(item?.text == flow.startedAt.formatted(date: .omitted, time: .standard))
        #expect(item?.help == "Started \(flow.startedAt.formatted(date: .abbreviated, time: .standard))")
    }
}
