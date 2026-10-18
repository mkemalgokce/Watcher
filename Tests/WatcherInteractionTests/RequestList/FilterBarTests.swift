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
            let model = try AppModel.demo()
            try await withWindow(showing: FlowListView().environment(model)) { window in
                #expect(model.list.visibleFlows.count == 5)
                #expect(await window.shows("Method"), "the list has drawn")
                #expect(window.elements("Clear Filters").isEmpty, "no summary row while nothing is filtered")

                FilterToken.apply([.status(4)], to: &model.list.query)
                #expect(await eventually { model.list.visibleFlows.map(\.response?.status) == [401, 403] })
                #expect(
                    await window.shows("2 of 5 requests"),
                    "the summary says how many are left"
                )

                try await window.press("Clear Filters")
                #expect(!model.list.query.isActive)
                #expect(model.list.visibleFlows.count == 5)
            }
        }

        @Test
        func noMatchesOffersClearFilters() async throws {
            let model = try AppModel.demo()
            model.list.query.text = "no-such-request"
            try await withWindow(showing: FlowListView().environment(model)) { window in
                #expect(model.list.visibleFlows.isEmpty)
                try await window.press("Clear Filters")
                #expect(model.list.query.text == "")
                #expect(model.list.visibleFlows.count == 5)
            }
        }
    }
}
