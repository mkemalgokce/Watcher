import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct AboutTests {
        @Test
        func aboutCopiesVersionInfo() async throws {
            let clipboard = ClipboardSpy()
            let model = try AppModel.test(clipboard: clipboard)
            try await withWindow(showing: AboutView().environment(model), width: 480, height: 640) { window in
                #expect(
                    !window.elements("Development build").isEmpty,
                    "an unbundled run says so instead of borrowing another version"
                )
                try await window.press("Copy Version Info")
                #expect(model.notice?.message == "Version info copied")
                let copied = clipboard.text
                #expect(copied?.hasPrefix("Watcher Development build · macOS") == true)
            }
        }
    }
}
