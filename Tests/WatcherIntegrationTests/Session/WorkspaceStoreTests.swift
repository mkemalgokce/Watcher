import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration))
struct WorkspaceStoreTests {
    @Test
    func aWorkspaceIsSavedOwnerOnlyAndOverwritingKeepsIt() throws {
        try withTemporaryDirectory(prefix: "watcher-workspace") { temporary in
            let store = WorkspaceStore(directory: temporary.appending("workspaces"))
            try store.save(name: "One", flows: [], settings: WatcherSettings())
            try store.save(name: "One", flows: [Flow.fixture()], settings: WatcherSettings())
            let file = temporary.appending("workspaces/One.workspace")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            #expect(permissions == 0o600)
            #expect(try store.load(name: "One").flows.count == 1)
        }
    }
}
