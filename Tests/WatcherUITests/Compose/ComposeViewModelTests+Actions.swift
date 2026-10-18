import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ComposeViewModelTests {
    /// What the buttons of the Compose window do, now that the view only calls them.
    @MainActor
    struct Actions {
        private let sender = RequestSenderSpy()
        private let files = FileAccessFake()

        private func model(
            panels: FilePanelsStub = FilePanelsStub(), proxyRunning: Bool = true
        ) async throws -> AppModel {
            let model = try AppModel(dependencies: .test(panels: panels, files: files, sender: sender))
            if proxyRunning {
                model.proxy.toggleRunning()
                #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
            }
            return model
        }

        private func viewModel(_ address: String = "https://api.example.com/x") -> ComposeViewModel {
            let viewModel = ComposeViewModel()
            viewModel.address = address
            return viewModel
        }

        @Test
        func beautifyAndMinifyRewriteTheBody() {
            let viewModel = viewModel()
            viewModel.bodyText = #"{"a":1}"#
            viewModel.beautifyBody()
            #expect(viewModel.bodyText == JSONFormatter.pretty(#"{"a":1}"#))
            viewModel.minifyBody()
            #expect(viewModel.bodyText == #"{"a":1}"#)
        }

        @Test
        func hasChangesFollowsTheEdits() {
            let viewModel = ComposeViewModel()
            viewModel.load(.fixture(method: "PUT"), asOriginal: true)
            #expect(!viewModel.hasChanges)
            viewModel.method = "POST"
            #expect(viewModel.hasChanges)
        }

        @Test
        func theWaitingTextNamesTheHostOrFallsBack() {
            #expect(viewModel("https://api.example.com/x").waitingText == "Waiting for api.example.com…")
            #expect(viewModel("not a url").waitingText == "Waiting for the server…")
        }

        private static let answerOK: (RequestRecord, Bool) async -> ResponseRecord = { _, _ in
            ResponseRecord(status: 200, headers: [], body: Data())
        }

        @Test
        func aResponseCanBeComparedOnlyForAnEditedRequestThatWasSent() async {
            let viewModel = viewModel()
            viewModel.load(.fixture(path: "/x"), asOriginal: true)
            #expect(viewModel.comparableRequest == nil, "nothing sent yet")
            await viewModel.send(isProxyRunning: true, perform: Self.answerOK)
            #expect(viewModel.comparableRequest?.path == "/x")

            let fresh = ComposeViewModel()
            fresh.address = "https://api.example.com/x"
            await fresh.send(isProxyRunning: true, perform: Self.answerOK)
            #expect(fresh.comparableRequest == nil, "not editing a captured request")
        }

        @Test
        func aChosenFileBecomesTheBodyAndACancelledPickKeepsTheOldOne() async throws {
            let url = URL(fileURLWithPath: "/fake-home/in/photo.png")
            try files.write(Data([1]), to: url.path)
            let viewModel = viewModel()
            let chosen = try await model(panels: FilePanelsStub(open: url), proxyRunning: false)
            await viewModel.chooseFile(using: chosen.filePicker)
            #expect(viewModel.file?.filename == "photo.png")

            let cancelled = try await model(proxyRunning: false)
            await viewModel.chooseFile(using: cancelled.filePicker)
            #expect(viewModel.file?.filename == "photo.png")
        }

        @Test
        func submittingAWebSocketAddressConnectsAndClosesTheWindow() async throws {
            let model = try await model()
            let viewModel = viewModel("ws://echo.test/socket")
            viewModel.bodyText = "hi\nthere"
            var dismissed = false
            await viewModel.submit(using: model.actions, isProxyRunning: true) { dismissed = true }
            #expect(dismissed)
            #expect(await eventually { sender.webSocketMessages == [["hi", "there"]] })
            #expect(sender.sent.isEmpty)
        }

        @Test
        func submittingAnHTTPAddressSendsItAndKeepsTheWindowOpen() async throws {
            let model = try await model()
            var dismissed = false
            let viewModel = viewModel()
            await viewModel.submit(using: model.actions, isProxyRunning: true) { dismissed = true }
            #expect(!dismissed)
            #expect(sender.sent.map(\.host) == ["api.example.com"])
            #expect(viewModel.result?.response?.status == 200)
        }

        @Test
        func connectingWhileTheProxyIsStoppedFailsInTheWindowAndStaysOpen() async throws {
            let model = try await model(proxyRunning: false)
            let viewModel = viewModel("ws://echo.test/socket")
            var dismissed = false
            await viewModel.submit(using: model.actions, isProxyRunning: false) { dismissed = true }
            #expect(!dismissed)
            #expect(viewModel.phase == .failed("Start the proxy to send requests."))
            #expect(sender.webSocketMessages.isEmpty)
        }
    }
}
