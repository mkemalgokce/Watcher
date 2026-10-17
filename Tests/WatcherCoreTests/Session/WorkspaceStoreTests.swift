import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct WorkspaceStoreTests {
    private let directory: TemporaryDirectory
    private let store: WorkspaceStore

    init() throws {
        directory = try TemporaryDirectory(prefix: "watcher-ws")
        store = WorkspaceStore(directory: directory.url)
    }

    @Test
    func savedWorkspaceLoadsBackAndCanBeDeleted() throws {
        var settings = WatcherSettings(); settings.noCaching = true
        let flow = Flow.fixture(request: .fixture(host: "a.com"), response: nil, state: .pending)
        try store.save(name: "Checkout bug", flows: [flow], settings: settings)
        #expect(store.list() == ["Checkout bug"])
        let loaded = try store.load(name: "Checkout bug")
        #expect(loaded.flows.count == 1); #expect(loaded.settings.noCaching)
        try store.delete(name: "Checkout bug")
        #expect(store.list().isEmpty)
    }

    @Test(arguments: ["../escape", "a/b", "", " lead", String(repeating: "x", count: 81)])
    func unsafeNamesAreRefused(_ name: String) {
        #expect(throws: (any Error).self, "\(name)") {
            try store.save(name: name, flows: [], settings: WatcherSettings())
        }
    }
}
