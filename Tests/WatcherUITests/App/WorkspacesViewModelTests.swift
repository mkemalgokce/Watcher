import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Saving the session and settings under a name and opening them again.
@MainActor
@Suite(.tags(.unit))
struct WorkspacesViewModelTests {
    private let files = FileAccessFake()
    private let notices = NoticeCenter.silent()

    private func make() throws -> (WorkspacesViewModel, WatcherEngine, SettingsEditor) {
        let engine = try WatcherEngine.inMemory(files: files)
        let settings = SettingsEditor(engine: engine, sleep: sleepUntilCancelled, notices: notices)
        return (WorkspacesViewModel(engine: engine, settings: settings, notices: notices), engine, settings)
    }

    @Test
    func savingAddsTheNameToTheList() throws {
        let (workspaces, _, _) = try make()
        #expect(workspaces.names.isEmpty)
        workspaces.save(named: "Checkout bug")
        #expect(workspaces.names == ["Checkout bug"])
        #expect(notices.notice == nil)
    }

    @Test
    func aFailedSaveIsReported() throws {
        let (workspaces, _, _) = try make()
        files.fail(.writeAtomically)
        files.fail(.writePrivately)
        workspaces.save(named: "x")
        #expect(notices.notice?.kind == .error)
        #expect(workspaces.names.isEmpty)
    }

    @Test
    func openingBringsBackTheSessionAndTheSettings() async throws {
        let (workspaces, engine, settings) = try make()
        var saved = engine.settings.value
        saved.maxFlows = 4321
        try engine.settings.replace(with: saved)
        engine.store.load([.fixture(sequence: 1, status: 200)])
        workspaces.save(named: "w")
        engine.store.load([])

        workspaces.open("w")
        #expect(await eventually { settings.value.maxFlows == 4321 })
        #expect(engine.store.all.count == 1)
    }

    @Test
    func openingAMissingWorkspaceIsReported() async throws {
        let (workspaces, _, _) = try make()
        workspaces.open("nope")
        #expect(await eventually { notices.notice?.kind == .error })
    }
}
