import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension AppModelTests {
    /// What the request actions do to the store, the clipboard and the notice shown.
    @MainActor
    struct Actions {
        private func model(with flows: [Flow]) -> AppModel {
            let model = AppModel(listening: false)
            model.engine.store.load(flows)
            model.syncFromStore()
            return model
        }

        @Test
        func starringAMixedSelectionStarsEveryRequest() {
            let starred = Flow.fixture(sequence: 1, status: 200, starred: true)
            let plain = Flow.fixture(sequence: 2, status: 200)
            let model = model(with: [starred, plain])
            model.toggleStar([starred.id, plain.id])
            #expect(!model.engine.store.all.contains { !$0.isStarred })
            #expect(model.notice?.message == "Starred")
        }

        @Test
        func starringAnAllStarredSelectionRemovesTheStars() {
            let flows = [1, 2].map { Flow.fixture(sequence: $0, status: 200, starred: true) }
            let model = model(with: flows)
            model.toggleStar(Set(flows.map(\.id)))
            #expect(model.engine.store.all.allSatisfy { !$0.isStarred })
            #expect(model.notice?.message == "Star removed")
        }

        @Test
        func sendingWhileStoppedAsksToStartTheProxy() {
            let model = AppModel(listening: false)
            model.send(.fixture())
            #expect(model.notice?.kind == .error)
            #expect(model.notice?.message == "Start the proxy to send requests.")
        }

        @Test
        func repeatingWhileStoppedAsksToStartTheProxy() {
            let model = AppModel(listening: false)
            model.repeatRequest(.fixture())
            #expect(model.notice?.message == "Start the proxy to send requests.")
        }

        @Test
        func copyPutsTheTextOnThePasteboardAndConfirms() {
            let model = AppModel(listening: false)
            model.copy("curl https://x.test", "Copied as cURL")
            #expect(model.pasteboard.string(forType: .string) == "curl https://x.test")
            #expect(model.notice?.kind == .success)
            #expect(model.notice?.message == "Copied as cURL")
        }

        @Test(arguments: ["", "hello world"])
        func composingFromAClipboardWithoutCurlIsRefused(clipboard: String) {
            let model = AppModel(listening: false)
            model.pasteboard.clearContents()
            model.pasteboard.setString(clipboard, forType: .string)
            model.composeFromClipboardCurl()
            #expect(model.sheet == nil)
            #expect(model.notice?.message == "Copy a curl command first, then choose New Request from cURL.")
        }

        @Test
        func composingFromABrokenCurlReportsWhy() {
            let model = AppModel(listening: false)
            model.pasteboard.clearContents()
            model.pasteboard.setString("curl 'https://x.test", forType: .string)
            model.composeFromClipboardCurl()
            #expect(model.sheet == nil)
            #expect(model.notice?.message.hasPrefix("Cannot read the cURL command") == true)
        }

        @Test
        func composingFromAValidCurlOpensCompose() {
            let model = AppModel(listening: false)
            model.composeSource = .fixture()
            model.pasteboard.clearContents()
            model.pasteboard.setString("curl -X POST https://x.test/v1", forType: .string)
            model.composeFromClipboardCurl()
            #expect(model.sheet == .compose)
            #expect(model.composeDraft?.method == "POST")
            #expect(model.composeDraft?.host == "x.test")
            #expect(model.composeSource == nil, "a pasted command has no captured original")
        }

        @Test
        func commentAndDeleteReachTheStore() {
            let flow = Flow.fixture(sequence: 1, status: 200)
            let model = model(with: [flow])
            model.setComment("look", for: flow.id)
            #expect(model.engine.store.all.first?.comment == "look")
            model.delete([flow.id])
            #expect(model.engine.store.all.isEmpty)
        }

        @Test
        func codeAddsTheProxyOnlyWhenAsked() {
            let model = AppModel(listening: false)
            let request = RequestRecord.fixture(host: "x.test", path: "/a")
            model.settings.includeProxyInCURL = false
            #expect(!model.code(for: request).contains(" -x "))
            model.settings.includeProxyInCURL = true
            #expect(model.code(for: request).contains("http://127.0.0.1:\(model.settings.port)"))
        }

        @Test
        func requestSearchFocusBumpsTheCounter() {
            let model = AppModel(listening: false)
            model.requestSearchFocus()
            model.requestSearchFocus()
            #expect(model.searchFocusRequest == 2)
        }

        @Test
        func errorMessageBecomesAnErrorNoticeAndResets() {
            let model = AppModel(listening: false)
            model.errorMessage = "broken"
            #expect(model.errorMessage == nil)
            #expect(model.notice?.kind == .error)
            #expect(model.notice?.message == "broken")
        }
    }
}
