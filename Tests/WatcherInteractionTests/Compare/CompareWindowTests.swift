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
            let model = try AppModel.demo()
            var request = model.list.flows[0].request
            request.headers.append(Header("X-Debug", "1"))
            let response = model.list.flows[0].response
            let other = Flow.fixture(sequence: 9, request: request, response: response, state: .completed)
            model.engine.store.load(model.list.flows + [other])
            model.list.syncFromStore()
            model.router.diffBase = model.list.flows[0]
            model.list.selection = model.list.flows.last?.id
            try await withWindow(showing: CompareWindow().environment(model), width: 900, height: 600) { window in
                #expect(
                    await eventually { !window.elements("No Differences").isEmpty },
                    "the response bodies are the same"
                )
                try await window.press("Headers")
                #expect(
                    await eventually { window.elements("No Differences").isEmpty },
                    "the added request header shows up as a difference"
                )
                #expect(await eventually { !window.elements("+1").isEmpty })
            }
        }
    }
}
