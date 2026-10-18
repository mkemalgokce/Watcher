import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Picking the headers and body of one half of an exchange.
@Suite(.tags(.unit))
struct FlowMessageSideTests {
    private static let flow = Flow.fixture(
        request: .fixture(headers: [Header("Accept", "*/*")], body: Data("up".utf8)),
        response: .fixture(headers: [Header("Server", "x")], body: Data("down".utf8))
    )

    @Test
    func theRequestSideIsTheRequest() {
        #expect(Self.flow.headers(.request) == [Header("Accept", "*/*")])
        #expect(Self.flow.body(.request) == Data("up".utf8))
    }

    @Test
    func theResponseSideIsTheResponse() {
        #expect(Self.flow.headers(.response) == [Header("Server", "x")])
        #expect(Self.flow.body(.response) == Data("down".utf8))
    }

    @Test
    func aMissingResponseIsEmpty() {
        let flow = Flow.fixture(response: nil)
        #expect(flow.headers(.response).isEmpty)
        #expect(flow.body(.response).isEmpty)
    }
}
