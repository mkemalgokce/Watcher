import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Which sections one side of an exchange offers, which one is shown, and the badges and summary on its header.
@Suite(.tags(.unit))
struct MessagePanelViewModelTests {
    typealias Section = MessagePanel.Section
    private static let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/"
        + "iZk9HQAAAABJRU5ErkJggg=="
    private static let embedded = Base64Finder.find(in: #"{"logo":"data:image/png;base64,\#(pixel)"}"#)

    private func model(
        _ flow: Flow,
        _ side: MessageSide,
        previewers: Bool = false,
        embedded: [Base64Segment] = []
    ) -> MessagePanelViewModel {
        MessagePanelViewModel(flow: flow, side: side, previewersActive: previewers, embedded: embedded)
    }

    @Test
    func paramsAreOnlyOnTheRequest() {
        let flow = Flow.fixture(request: .fixture(body: Data("x".utf8)))
        #expect(model(flow, .request).available == [.headers, .params, .body, .cookies, .raw])
        #expect(model(flow, .response).available == [.headers, .body, .cookies, .raw])
    }

    @Test
    func messagesAreOnlyOnAWebSocketResponse() {
        let socket = Flow.fixture(sequence: 1, status: 101)
        #expect(model(socket, .response).available.contains(.messages))
        #expect(!model(socket, .request).available.contains(.messages))
        #expect(!model(.fixture(sequence: 1, status: 200), .response).available.contains(.messages))
    }

    @Test
    func previewersOnlyWhenTheToolIsOn() {
        #expect(model(.fixture(), .response, previewers: true).available.contains(.previewers))
        #expect(!model(.fixture(), .request, previewers: true).available.contains(.previewers))
        #expect(!model(.fixture(), .response).available.contains(.previewers))
    }

    @Test
    func decodedOnlyWithEmbeddedData() {
        #expect(!Self.embedded.isEmpty)
        #expect(model(.fixture(), .response, embedded: Self.embedded).available.contains(.decoded))
        #expect(model(.fixture(), .response, embedded: Self.embedded).count(.decoded) == Self.embedded.count)
        #expect(!model(.fixture(), .response).available.contains(.decoded))
    }

    @Test(arguments: [("Headers", Section.headers), ("Raw", .raw), ("Messages", .body), ("nonsense", .body)])
    func aSectionTheExchangeLacksFallsBackToBody(chosen: String, expected: Section) {
        let flow = Flow.fixture(request: .fixture(body: Data("x".utf8)))
        #expect(model(flow, .request).section(chosen: chosen) == expected)
    }

    /// A Body tab that could only ever jump elsewhere when clicked is not offered at all.
    @Test
    func aRequestWithoutABodyHasNoBodyTab() {
        #expect(!model(.fixture(request: .fixture(path: "/")), .request).available.contains(.body))
        #expect(model(.fixture(request: .fixture(body: Data("x".utf8))), .request).available.contains(.body))
        #expect(model(.fixture(response: .fixture()), .response).available.contains(.body))
    }

    @Test
    func anEmptyRequestBodyShowsTheParametersOrElseTheHeaders() {
        let withQuery = Flow.fixture(request: .fixture(path: "/search?q=1"))
        #expect(model(withQuery, .request).section(chosen: "Body") == .params)
        #expect(model(.fixture(request: .fixture(path: "/")), .request).section(chosen: "Body") == .headers)
        #expect(model(.fixture(response: .fixture()), .response).section(chosen: "Body") == .body)
    }

    @Test
    func badgesCountWhatEachSectionHolds() {
        let request = RequestRecord.fixture(
            path: "/a?x=1&y=2",
            headers: [Header("Cookie", "a=1; b=2"), Header("Accept", "*/*")]
        )
        let panel = model(.fixture(request: request), .request)
        #expect(panel.count(.headers) == 2)
        #expect(panel.count(.params) == 2)
        #expect(panel.count(.cookies) == 2)
        #expect(panel.count(.body) == nil)
        #expect(panel.count(.raw) == nil)
    }

    @Test
    func theDetailNamesTheTypeAndSize() {
        let text = [Header("Content-Type", "text/plain; charset=utf-8")]
        let response = ResponseRecord.fixture(headers: text, body: Data("hi".utf8))
        #expect(model(.fixture(response: response), .response).detail == "text/plain · 2 B")
    }

    @Test
    func anEmptyResponseStillStatesItsSize() {
        #expect(model(.fixture(response: .fixture()), .response).detail == "0 B")
        #expect(model(.fixture(), .request).detail.isEmpty, "an empty request body is not sized")
    }
}
