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
            try await withWindow(showing: ComposeView().environment(model), width: 900, height: 640) { window in
                #expect(!window.elements("Start Proxy").isEmpty, "the empty response pane offers to start the proxy")
                try await window.press("Send")
                await settle(0.3)
                #expect(!window.elements("Not Sent").isEmpty, "a send with the proxy stopped shows why")
            }
        }
    }
}
