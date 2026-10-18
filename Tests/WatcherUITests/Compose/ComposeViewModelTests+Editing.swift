import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ComposeViewModelTests {
    /// What the window shows while editing a captured request, and how a draft handed to it is taken up.
    @MainActor
    struct Editing {
        private let notices = NoticeCenter.silent()
        private let draft = RequestRecord.fixture(method: "PUT", path: "/v1/items")

        private func router() -> WindowRouter {
            WindowRouter(notices: notices, focusFilterField: {})
        }

        @Test
        func aDraftIsTakenOnceAndRemembersItsOriginalOnlyWhenItCameFromARequest() {
            let router = router()
            router.composeDraft = draft
            let viewModel = ComposeViewModel()
            viewModel.loadDraft(from: router)
            #expect(viewModel.method == "PUT")
            #expect(viewModel.original == nil)
            #expect(router.composeDraft == nil, "taken")

            router.composeDraft = draft
            router.composeSource = .fixture()
            viewModel.loadDraft(from: router)
            #expect(viewModel.original?.path == "/v1/items")
        }

        @Test
        func withoutADraftNothingChanges() {
            let viewModel = ComposeViewModel()
            viewModel.loadDraft(from: router())
            #expect(viewModel.method == "GET")
        }

        @Test
        func theBannerSaysWhetherAnythingChanged() {
            let viewModel = ComposeViewModel()
            viewModel.load(draft, asOriginal: true)
            #expect(viewModel.changesSummary == "No changes yet: sending repeats it as captured.")
            viewModel.method = "POST"
            viewModel.headers.append(KeyValue("X-New", "1"))
            #expect(viewModel.changesSummary == "Changed: method, 1 header")
        }

        @Test
        func copyingAsCURLPutsTheBuiltRequestOnTheClipboardOrReportsTheProblem() throws {
            let clipboard = ClipboardSpy()
            let model = try AppModel(dependencies: .test(clipboard: clipboard))
            let viewModel = ComposeViewModel()
            viewModel.address = "https://api.example.com/x"
            viewModel.copyAsCURL(using: model.actions)
            #expect(clipboard.text?.contains("api.example.com/x") == true)
            #expect(viewModel.problem == nil)

            viewModel.address = "nonsense"
            viewModel.copyAsCURL(using: model.actions)
            #expect(viewModel.problem == "Enter a full http:// or https:// URL.")
        }
    }
}
