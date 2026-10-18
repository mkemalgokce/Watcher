import Observation
import WatcherCore

/// Named snapshots of the session and settings (File ▸ Workspaces).
@MainActor @Observable
final class WorkspacesViewModel {
    private(set) var names: [String]
    @ObservationIgnored private let engine: WatcherEngine
    @ObservationIgnored private let settings: SettingsEditor
    @ObservationIgnored private let notices: NoticeCenter

    init(engine: WatcherEngine, settings: SettingsEditor, notices: NoticeCenter) {
        self.engine = engine; self.settings = settings; self.notices = notices
        names = engine.workspaces.list()
    }

    func save(named name: String) {
        do {
            try engine.saveWorkspace(named: name)
            names = engine.workspaces.list()
        } catch { notices.notify("\(error)", .error) }
    }

    func open(_ name: String) {
        Task {
            do {
                try await engine.openWorkspace(named: name)
                settings.value = engine.settings.value
            } catch { notices.notify("\(error)", .error) }
        }
    }
}
