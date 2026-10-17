import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct FilterBarTests {
        @Test
        func tokensFilterTheListAndTheSummaryClearsThem() async throws {
            let model = AppModel.preview()
            try await withWindow(showing: FlowListView().environment(model)) { window in
                #expect(model.visibleFlows.count == 5)
                #expect(window.elements("Clear Filters").isEmpty, "no summary row while nothing is filtered")

                FilterToken.apply([.status(4)], to: &model.query)
                await settle()
                #expect(model.visibleFlows.map(\.response?.status) == [401, 403])
                #expect(!window.elements("2 of 5 requests").isEmpty, "the summary says how many are left")

                try await window.press("Clear Filters")
                #expect(!model.query.isActive)
                #expect(model.visibleFlows.count == 5)
            }
        }

        @Test
        func noMatchesOffersClearFilters() async throws {
            let model = AppModel.preview()
            model.query.text = "no-such-request"
            try await withWindow(showing: FlowListView().environment(model)) { window in
                #expect(model.visibleFlows.isEmpty)
                try await window.press("Clear Filters")
                #expect(model.query.text == "")
                #expect(model.visibleFlows.count == 5)
            }
        }
    }
}
