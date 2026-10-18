import AppKit
import Testing
import WatcherTestSupport
import WatcherUI

@MainActor
@Suite(.tags(.unit))
struct AppDelegateTests {
    @Test
    func closingTheLastWindowKeepsWatcherCapturingFromTheMenuBar() {
        #expect(!AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
