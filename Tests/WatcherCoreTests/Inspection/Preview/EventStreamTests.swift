import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct EventStreamTests {
    @Test
    func parsesEventsLikeEventSource() throws {
        let text = ": keep-alive\r\nid: 1\r\nevent: price\r\ndata: {\"a\":1}\r\n\r\n"
            + "data: line one\ndata: line two\n\nretry: 3000\nevent: done\n"
        let events = EventStream.parse(text)
        try #require(events.count == 3)
        #expect(events[0] == .init(id: "1", event: "price", data: #"{"a":1}"#, retry: nil))
        #expect(events[1].data == "line one\nline two"); #expect(events[1].event == nil)
        #expect(events[2].event == "done"); #expect(events[2].retry == 3000); #expect(events[2].data == "")
        #expect(EventStream.parse("").isEmpty)
    }
}
