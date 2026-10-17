import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct CompareWindowTests {
        @Test
        func compareSwitchesWhatItCompares() async throws {
            let model = AppModel.preview()
            var request = model.flows[0].request
            request.headers.append(Header("X-Debug", "1"))
            let response = model.flows[0].response
            let other = Flow.fixture(sequence: 9, request: request, response: response, state: .completed)
            model.engine.store.load(model.flows + [other])
            model.syncFromStore()
            model.diffBase = model.flows[0]
            model.selection = model.flows.last?.id
            try await withWindow(showing: CompareWindow().environment(model), width: 900, height: 600) { window in
                await settle(1)
                #expect(!window.elements("No Differences").isEmpty, "the response bodies are the same")
                try await window.press("Headers")
                await settle(1)
                #expect(window.elements("No Differences").isEmpty, "the added request header shows up as a difference")
                #expect(!window.elements("+1").isEmpty)
            }
        }
    }
}
