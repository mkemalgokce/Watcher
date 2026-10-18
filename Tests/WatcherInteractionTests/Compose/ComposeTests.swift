import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct ComposeTests {
        @Test
        func composeExplainsWhyItCannotSendYet() async throws {
            let model = try AppModel.test()
            let compose = ComposeView(now: model.now).environment(model)
            try await withWindow(showing: compose, width: 900, height: 640) { window in
                #expect(await window.shows("Start Proxy"), "the empty response pane offers to start the proxy")
                try await window.press("Send")
                #expect(
                    await eventually { !window.elements("Not Sent").isEmpty },
                    "a send with the proxy stopped shows why"
                )
            }
        }
    }
}
