import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HARTests {
    @Test
    func exportThenImportKeepsURLBodyStatusAndDuration() throws {
        let imported = try HAR.flows(from: HAR.export([Flow.jsonPostFixture()]))
        let flow = try #require(imported.first)
        #expect(flow.request.url == "https://api.example.com/v1/users?id=7")
        #expect(flow.request.body == Data(#"{"name":"it's"}"#.utf8))
        #expect(flow.response?.status == 201)
        #expect(abs((flow.duration ?? 0) - 0.25) <= 0.001)
    }
}
