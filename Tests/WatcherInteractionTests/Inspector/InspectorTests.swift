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
        func inspectorHeaderActions() async throws {
            let model = AppModel.preview()
            model.observeEngine()
            let selected = model.flows[0]
            try await withWindow(showing: FlowDetailView().environment(model), width: 900) { window in
                try await window.press("Star")
                await settle(0.3) // the star goes through the store and comes back as an event batch
                #expect(model.flows[0].isStarred)
                #expect(!window.elements("Remove Star").isEmpty, "the button now offers to undo")

                try await window.press("Copy as cURL")
                #expect(model.notice?.message == "cURL copied")
                #expect(model.pasteboard.string(forType: .string) == model.code(for: selected.request, as: .curl))
                #expect(model.pasteboard != NSPasteboard.general, "tests must never write to the real clipboard")

                try await window.press("Edit & Repeat")
                #expect(model.sheet == .compose)
                #expect(model.composeDraft?.url == selected.request.url)
            }
        }

        @Test
        func narrowInspectorSwitchesBetweenRequestAndResponse() async throws {
            let model = AppModel.preview()
            model.exchangeSide = .response
            try await withWindow(showing: FlowDetailView().environment(model), width: 420) { window in
                try await window.press("Request")
                #expect(model.exchangeSide == .request)
                try await window.press("Response")
                #expect(model.exchangeSide == .response)
            }
        }
    }
}
