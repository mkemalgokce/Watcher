import Testing
import WatcherTestSupport

/// The app's scene declaration, read from its source.
struct WatcherAppTests {
    /// MenuBarExtra(isInserted:) writes its binding back on every update; bound to @AppStorage that loops and froze the
    /// app at launch.
    @Test
    func menuBarItemHasNoInsertedBinding() throws {
        let app = try SourceTree.text("Sources/Watcher/WatcherApp.swift")
        #expect(app.contains("MenuBarExtra"))
        #expect(!app.contains("isInserted:"))
    }
}
