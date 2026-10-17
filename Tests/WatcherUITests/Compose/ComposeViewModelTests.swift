import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The Compose window's form: URL and parameters, pasted cURL, building and sending, and Edit & Repeat.
@MainActor
struct ComposeViewModelTests {
    private static let captured = RequestRecord.fixture(
        method: "POST",
        path: "/v1/items?x=1",
        headers: [Header("Content-Type", "application/json"), Header("X-Trace", "1"), Header("Content-Length", "11")],
        body: Data(#"{"name":"A"}"#.utf8)
    )

    @Test
    func composeKeepsURLAndParamsInSync() {
        let viewModel = ComposeViewModel()
        viewModel.address = "https://api.example.com/search?q=swift&page=2"
        #expect(viewModel.params.map(\.name) == ["q", "page"])
        viewModel.params[1].value = "3"
        #expect(viewModel.address == "https://api.example.com/search?q=swift&page=3")
        viewModel.params[0].isEnabled = false
        #expect(viewModel.address == "https://api.example.com/search?page=3")
        #expect(viewModel.params.count == 2, "a switched-off parameter stays in the list")
        #expect(viewModel.badge(.params) == "1")
    }

    @Test
    func pastingCurlFillsTheForm() {
        let viewModel = ComposeViewModel()
        viewModel.address = """
        curl -X POST 'https://api.example.com/v1/items' -H 'Content-Type: application/json' --data-raw '{"name":"A"}'
        """
        #expect(viewModel.method == "POST")
        #expect(viewModel.address == "https://api.example.com/v1/items")
        #expect(viewModel.bodyKind == .json)
        #expect(viewModel.bodyText == #"{"name":"A"}"#)
        #expect(viewModel.tab == .body)
        #expect(viewModel.problem == nil)
    }

    @Test
    func brokenCurlIsReported() {
        let viewModel = ComposeViewModel()
        viewModel.address = "curl -H"
        #expect(viewModel.problem != nil)
    }

    @Test
    func buildAddsAuthAndRejectsBadURLs() throws {
        let viewModel = ComposeViewModel()
        viewModel.address = "ftp://example.com"
        #expect(throws: (any Error).self) { try viewModel.build() }
        viewModel.address = "https://api.example.com:8443/x"
        viewModel.auth = .bearer; viewModel.token = "t0k"
        let request = try viewModel.build()
        #expect(request.port == 8443)
        #expect(request.headers.value(for: "Authorization") == "Bearer t0k")
        viewModel.headers.append(KeyValue("Authorization", "Custom"))
        #expect(try viewModel.build().headers.value(for: "Authorization") == "Custom", "a header you add wins")
        viewModel.bodyKind = .binary
        #expect(throws: (any Error).self, "binary without a file") { try viewModel.build() }
    }

    @Test
    func sendStates() async {
        let viewModel = ComposeViewModel()
        viewModel.address = "https://api.example.com/x"
        await viewModel.send(isProxyRunning: false) { _, _ in
            Issue.record("must not send"); return .fixture()
        }
        #expect(viewModel.phase == .failed("Start the proxy to send requests."))

        await viewModel.send(isProxyRunning: true) { request, follow in
            #expect(!follow)
            #expect(request.host == "api.example.com")
            return .fixture(status: 201, body: Data("ok".utf8))
        }
        #expect(viewModel.result?.response?.status == 201)
        #expect(viewModel.problem == nil)

        await viewModel.send(isProxyRunning: true) { _, _ in .fixture(status: 502, body: Data("down".utf8)) }
        #expect(viewModel.result?.response?.status == 502, "the error answer is still shown")
        #expect(viewModel.problem == "The server answered 502 Bad Gateway. See the response below.")

        viewModel.address = "nonsense"
        await viewModel.send(isProxyRunning: true) { _, _ in
            Issue.record("must not send"); return .fixture()
        }
        if case .failed = viewModel.phase {} else {
            Issue.record("an invalid URL fails before sending")
        }
    }

    @Test
    func loadingACapturedRequestDropsTransportHeaders() {
        let viewModel = ComposeViewModel()
        viewModel.load(.fixture(
            method: "PUT",
            host: "h.example",
            path: "/a?x=1",
            headers: [Header("Host", "h.example"), Header("Content-Length", "2"), Header("X-Keep", "1")],
            body: Data("hi".utf8)
        ))
        #expect(viewModel.method == "PUT")
        #expect(viewModel.headers.map(\.name) == ["X-Keep"])
        #expect(viewModel.params.map(\.name) == ["x"])
        #expect(viewModel.bodyText == "hi")
    }

    @Test
    func editAndRepeatListsChangesAndResets() {
        let viewModel = ComposeViewModel()
        viewModel.load(Self.captured, asOriginal: true)
        #expect(viewModel.changes == [], "loading alone changes nothing; transport headers do not count")

        viewModel.method = "PUT"
        viewModel.headers.removeAll { $0.name == "X-Trace" }
        viewModel.bodyText = #"{"name":"B"}"#
        #expect(viewModel.changes == ["method", "1 header", "body"])
        viewModel.address = "https://api.example.com/v2/items?x=1"
        #expect(viewModel.changes.contains("URL"))

        viewModel.resetToOriginal()
        #expect(viewModel.changes == [])
        #expect(viewModel.method == "POST")
        #expect(viewModel.address == Self.captured.url)
        #expect(viewModel.phase == .idle)
    }

    @Test
    func newRequestHasNoOriginal() {
        let viewModel = ComposeViewModel()
        viewModel.load(Self.captured)
        #expect(viewModel.original == nil)
        #expect(viewModel.changes == [])
        viewModel.resetToOriginal() // nothing to go back to: no-op
        #expect(viewModel.method == "POST")
    }
}
