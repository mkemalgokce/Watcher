import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The windows and sheets the main window opens: Compose, Compare, Converter, Breakpoints and Help.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct WindowScreenTests {
    private static let composeSize = CGSize(width: 920, height: 720)

    private func compose(_ configure: (ComposeViewModel) async -> Void) async throws -> some View {
        let viewModel = ComposeViewModel(now: { Screen.started }, boundary: { "boundary" })
        await configure(viewModel)
        return try ComposeView(viewModel: viewModel).environment(Screen.model())
    }

    private func jsonPost(_ viewModel: ComposeViewModel) {
        viewModel.method = "POST"
        viewModel.address = "https://api.example.com/v1/users?page=2"
        viewModel.bodyKind = .json
        viewModel.bodyText = #"{"name":"Ada","role":"admin"}"#
        viewModel.tab = .body
    }

    @Test
    func composeBeforeSending() async throws {
        let view = try await compose { jsonPost($0) }
        await ImageSnapshot.verify(view, size: Self.composeSize, named: "http")
    }

    @Test
    func composeWithTheAnswer() async throws {
        let answer = ResponseRecord.fixture(
            status: 201, headers: [Header("Content-Type", "application/json")],
            body: Screen.json(#"{"id":7,"name":"Ada"}"#)
        )
        let view = try await compose { viewModel in
            jsonPost(viewModel)
            await viewModel.send(isProxyRunning: true) { _, _ in answer }
        }
        await ImageSnapshot.verify(view, size: Self.composeSize, named: "answered")
    }

    @Test
    func composeForAWebSocket() async throws {
        let view = try await compose { viewModel in
            viewModel.address = "wss://chat.example.com/socket"
            viewModel.bodyKind = .text
            viewModel.bodyText = #"{"type":"join","room":"general"}"#
            viewModel.tab = .body
        }
        await ImageSnapshot.verify(view, size: Self.composeSize, named: "webSocket")
    }

    @Test
    func composeWhileTheProxyIsStopped() async throws {
        let view = try await compose { viewModel in
            jsonPost(viewModel)
            await viewModel.send(isProxyRunning: false) { _, _ in .fixture() }
        }
        await ImageSnapshot.verify(view, size: Self.composeSize, named: "cannotSend")
    }

    @Test
    func compareTwoResponses() async throws {
        let url = "https://api.example.com/v1/me"
        let base = Screen.exchange(1, "GET", url, body: Screen.json(#"{"id":1,"plan":"free"}"#))
        let current = Screen.exchange(2, "GET", url, body: Screen.json(#"{"id":1,"plan":"pro","seats":3}"#))
        let model = try Screen.model(flows: [base, current], selecting: current)
        model.router.diffBase = base
        await ImageSnapshot.verify(
            CompareWindow().environment(model), size: CGSize(width: 900, height: 560), named: "changed"
        )
    }

    @Test
    func compareWithoutASelection() async throws {
        try await ImageSnapshot.verify(
            CompareWindow().environment(Screen.model()), size: CGSize(width: 900, height: 560), named: "none"
        )
    }

    @Test
    func theConverterBeforeInput() async throws {
        try await ImageSnapshot.verify(
            ConverterView().environment(Screen.model()), size: CGSize(width: 680, height: 520), named: "empty"
        )
    }

    @Test
    func theConverterWithAResult() async throws {
        let converter = ConverterViewModel()
        converter.input = "SGVsbG8sIFdhdGNoZXIh"
        try await ImageSnapshot.verify(
            ConverterView(converter: converter).environment(Screen.model()), size: CGSize(width: 680, height: 520),
            named: "decoded"
        )
    }

    @Test
    func theConverterWithABadInput() async throws {
        let converter = ConverterViewModel()
        converter.input = "%%% not base64"
        try await ImageSnapshot.verify(
            ConverterView(converter: converter).environment(Screen.model()), size: CGSize(width: 680, height: 520),
            named: "failed"
        )
    }

    @Test(arguments: HelpView.Page.allCases)
    func help(page: HelpView.Page) async {
        await ImageSnapshot.verify(HelpView(page: page), size: CGSize(width: 640, height: 560), named: page.rawValue)
    }
}
