import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct WorkspaceStoreTests {
    private let directory = URL(fileURLWithPath: "/fake-home/.watcher/workspaces")
    private let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let files = FileAccessFake()
    private var store: WorkspaceStore {
        WorkspaceStore(directory: directory, files: files.access, now: { [savedAt] in savedAt })
    }

    @Test
    func savedWorkspaceLoadsBackAndCanBeDeleted() throws {
        var settings = WatcherSettings(); settings.noCaching = true
        let flow = Flow.fixture(request: .fixture(host: "a.com"), response: nil, state: .pending)
        try store.save(name: "Checkout bug", flows: [flow], settings: settings)
        #expect(files.folders.contains(directory.path))
        #expect(store.list() == ["Checkout bug"])
        let loaded = try store.load(name: "Checkout bug")
        #expect(loaded.flows.count == 1); #expect(loaded.settings.noCaching)
        try store.delete(name: "Checkout bug")
        #expect(store.list().isEmpty)
    }

    @Test
    func aSavedWorkspaceIsStampedWithTheCurrentTime() throws {
        try store.save(name: "Now", flows: [], settings: WatcherSettings())
        #expect(try store.load(name: "Now").savedAt == savedAt)
    }

    @Test
    func theListHoldsOnlyWorkspaceFilesInNameOrder() {
        for name in ["b.workspace", "A.workspace", "notes.txt", "c.workspace.bak"] {
            files.write(Data(), to: directory.appendingPathComponent(name).path)
        }
        files.write(Data(), to: "/fake-home/.watcher/elsewhere.workspace")
        #expect(store.list() == ["A", "b"])
    }

    @Test
    func aMissingFolderListsNothing() {
        files.fail(.contentsOfDirectory)
        #expect(store.list().isEmpty)
    }

    @Test
    func deletingAnUnknownWorkspaceThrows() {
        #expect(throws: (any Error).self) { try store.delete(name: "Never saved") }
    }

    @Test
    func loadingAnUnknownWorkspaceThrows() {
        #expect(throws: (any Error).self) { try store.load(name: "Never saved") }
    }

    @Test
    func aFailedWriteIsReported() {
        files.fail(.writeAtomically)
        #expect(throws: FileAccessFake.Failure(operation: .writeAtomically)) {
            try store.save(name: "Draft", flows: [], settings: WatcherSettings())
        }
    }

    @Test(arguments: ["../escape", "a/b", "", " lead", "trail ", String(repeating: "x", count: 81)])
    func unsafeNamesAreRefused(_ name: String) {
        #expect(throws: WorkspaceStore.InvalidName.self, "\(name)") {
            try store.save(name: name, flows: [], settings: WatcherSettings())
        }
        #expect(files.paths.isEmpty)
    }
}
