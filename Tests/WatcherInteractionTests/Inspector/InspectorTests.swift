import AppKit
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct InspectorTests {
        @Test
        func headerButtonsStarCopyAndRepeatTheRequest() async throws {
            let model = try AppModel.demo()
            model.observeEngine()
            let selected = model.list.flows[0]
            try await withWindow(showing: FlowDetailView().environment(model), width: 900) { window in
                try await window.press("Star")
                await settle(0.3) // the star goes through the store and comes back as an event batch
                #expect(model.list.flows[0].isStarred)
                #expect(!window.elements("Remove Star").isEmpty, "the button now offers to undo")

                try await window.press("Copy as cURL")
                #expect(model.notices.notice?.message == "cURL copied")
                #expect(model.clipboard.string() == model.actions.code(for: selected.request, as: .curl))

                try await window.press("Edit & Repeat")
                #expect(model.router.sheet == .compose)
                #expect(model.router.composeDraft?.url == selected.request.url)
            }
        }

        @Test
        func narrowInspectorSwitchesBetweenRequestAndResponse() async throws {
            let model = try AppModel.demo()
            model.router.exchangeSide = .response
            try await withWindow(showing: FlowDetailView().environment(model), width: 420) { window in
                try await window.press("Request")
                #expect(model.router.exchangeSide == .request)
                try await window.press("Response")
                #expect(model.router.exchangeSide == .response)
            }
        }
    }
}
