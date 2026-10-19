import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Editing a message paused at a breakpoint.
@MainActor
@Suite(.tags(.unit))
struct HitEditorViewModelTests {
    private static let login = RequestRecord.fixture(
        method: "POST",
        path: "/v1/login",
        headers: [Header("Content-Type", "application/json"), Header("Content-Length", "14")],
        body: Data(#"{"user":"ada"}"#.utf8)
    )

    @Test
    func editedRequestIsRebuiltFromTheForm() {
        let viewModel = HitEditorViewModel(hit: .init(phase: .request, request: Self.login))
        #expect(viewModel.urlText == "https://api.example.com/v1/login")
        viewModel.method = "PUT"
        viewModel.urlText = "http://staging.example.com:8080/v2/login?x=1"
        viewModel.bodyText = #"{"user":"grace"}"#
        guard case let .proceed(request, response) = viewModel.resolution() else {
            Issue.record("expected an edited request")
            return
        }
        #expect(response == nil)
        #expect(request.method == "PUT")
        #expect(request.scheme == "http"); #expect(request.host == "staging.example.com"); #expect(request.port == 8080)
        #expect(request.path == "/v2/login?x=1")
        #expect(request.headers.value(for: "Content-Length") == nil, "a stale length would cut the edited body")
        #expect(String(data: request.body, encoding: .utf8) == #"{"user":"grace"}"#)
    }

    @Test(arguments: ["", "api.example.com/x", "ftp://example.com/x", "https://"])
    func aRequestWithAnInvalidURLCannotBeSent(url: String) {
        let request = HitEditorViewModel(hit: .init(phase: .request, request: Self.login))
        request.urlText = url
        #expect(!request.canExecute)
        #expect(request.resolution() == nil)
    }

    @Test(arguments: ["", "abc", "99", "600"])
    func aResponseWithAnInvalidStatusCannotBeSent(status: String) {
        let response = Self.pausedResponse()
        response.status = status
        #expect(!response.canExecute)
    }

    @Test
    func spacesAroundTheStatusAreIgnored() {
        let response = Self.pausedResponse()
        response.status = " 404 "
        #expect(response.statusCode == 404)
    }

    private static func pausedResponse() -> HitEditorViewModel {
        HitEditorViewModel(hit: .init(phase: .response, request: login, response: .fixture()))
    }

    @Test
    func editedResponseAndTemplates() {
        let viewModel = HitEditorViewModel(hit: .init(
            phase: .response,
            request: Self.login,
            response: .fixture(headers: [Header("Content-Type", "application/json")], body: Data(#"{"a":1}"#.utf8))
        ))
        #expect(viewModel.isResponse)
        #expect(viewModel.bodyLanguage == .json)
        let template = BreakpointTemplate.builtIn[0]
        viewModel.apply(template)
        #expect(viewModel.status == "\(template.status)")
        guard case let .proceed(_, edited) = viewModel.resolution(), let response = edited else {
            Issue.record("expected an edited response")
            return
        }
        #expect(response.status == template.status)
        #expect(String(data: response.body, encoding: .utf8) == template.body)
    }

    @Test
    func beautifyRewritesTheBodyAsPrettyJSON() {
        let viewModel = HitEditorViewModel(hit: .init(phase: .request, request: Self.login))
        viewModel.bodyText = #"{"a":1}"#
        viewModel.beautifyBody()
        #expect(viewModel.bodyText == JSONFormatter.pretty(#"{"a":1}"#))
    }
}
