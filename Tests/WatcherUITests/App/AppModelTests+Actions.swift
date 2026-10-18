import AppKit
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
            #expect(model.notices.notice?.message == "Starred")
        }

        @Test
        func starringAnAllStarredSelectionRemovesTheStars() {
            let flows = [1, 2].map { Flow.fixture(sequence: $0, status: 200, starred: true) }
            let model = model(with: flows)
            model.toggleStar(Set(flows.map(\.id)))
            #expect(model.engine.store.all.allSatisfy { !$0.isStarred })
            #expect(model.notices.notice?.message == "Star removed")
        }

        @Test
        func sendingWhileStoppedAsksToStartTheProxy() {
            let model = AppModel(listening: false)
            model.send(.fixture())
            #expect(model.notices.notice?.kind == .error)
            #expect(model.notices.notice?.message == "Start the proxy to send requests.")
        }

        @Test
        func repeatingWhileStoppedAsksToStartTheProxy() {
            let model = AppModel(listening: false)
            model.repeatRequest(.fixture())
            #expect(model.notices.notice?.message == "Start the proxy to send requests.")
        }

        @Test
        func copyPutsTheTextOnThePasteboardAndConfirms() throws {
            let clipboard = ClipboardSpy()
            let model = try AppModel.test(clipboard: clipboard)
            model.copy("curl https://x.test", "Copied as cURL")
            #expect(clipboard.text == "curl https://x.test")
            #expect(model.notices.notice?.kind == .success)
            #expect(model.notices.notice?.message == "Copied as cURL")
        }

        @Test
        func copyingAnImagePutsItOnThePasteboard() throws {
            let clipboard = ClipboardSpy()
            let model = try AppModel.test(clipboard: clipboard)
            model.copy(image: NSImage(size: NSSize(width: 1, height: 1)))
            #expect(clipboard.images.count == 1)
            #expect(model.notices.notice?.message == "Image copied")
        }

        @Test(arguments: [nil, "", "hello world"])
        func composingFromAClipboardWithoutCurlIsRefused(clipboard: String?) throws {
            let model = try AppModel.test(clipboard: ClipboardSpy(text: clipboard))
            model.composeFromClipboardCurl()
            #expect(model.sheet == nil)
            #expect(model.notices.notice?.message == "Copy a curl command first, then choose New Request from cURL.")
        }

        @Test
        func composingFromABrokenCurlReportsWhy() throws {
            let model = try AppModel.test(clipboard: ClipboardSpy(text: "curl 'https://x.test"))
            model.composeFromClipboardCurl()
            #expect(model.sheet == nil)
            #expect(model.notices.notice?.message.hasPrefix("Cannot read the cURL command") == true)
        }

        @Test
        func composingFromAValidCurlOpensCompose() throws {
            let model = try AppModel.test(clipboard: ClipboardSpy(text: "curl -X POST https://x.test/v1"))
            model.composeSource = .fixture()
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
    }
}
