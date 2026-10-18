import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The engine with nothing listening: its session and workspace handling, on an in-memory file system.
@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct WatcherEngineTests {
    private let files = FileAccessFake()

    private func engine() throws -> WatcherEngine {
        try .inMemory(files: files)
    }

    @Test
    func aSavedWorkspaceBringsBackTheSessionAndTheSettings() async throws {
        let engine = try engine()
        try engine.settings.update { $0.port = 9111; $0.noCaching = true }
        engine.store.load([.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 404)])
        try engine.saveWorkspace(named: "debug")

        engine.store.clear()
        try engine.settings.update { $0.port = 8000; $0.noCaching = false }
        try await engine.openWorkspace(named: "debug")

        #expect(engine.store.all.map(\.request.path) == ["/1", "/2"])
        #expect(engine.settings.value.port == 9111)
        #expect(engine.settings.value.noCaching)
        #expect(engine.workspaces.list() == ["debug"])
    }

    @Test
    func openingAWorkspaceReplacesTheSessionInsteadOfAddingToIt() async throws {
        let engine = try engine()
        engine.store.load([.fixture(sequence: 1, status: 200)])
        try engine.saveWorkspace(named: "one")
        engine.store.load([.fixture(sequence: 1, status: 201), .fixture(sequence: 2, status: 202)])
        try await engine.openWorkspace(named: "one")
        #expect(engine.store.all.count == 1)
    }

    @Test
    func openingAnUnknownWorkspaceChangesNothing() async throws {
        let engine = try engine()
        engine.store.load([.fixture(sequence: 1, status: 200)])
        await #expect(throws: (any Error).self) { try await engine.openWorkspace(named: "missing") }
        #expect(engine.store.all.count == 1)
    }
}
