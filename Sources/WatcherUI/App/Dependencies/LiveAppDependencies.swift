import AppKit
import WatcherCore

extension AppDependencies {
    /// The real app: ~/.watcher and the general pasteboard.
    static func live() -> AppDependencies {
        let engine = makeEngine(in: WatcherPaths.supportDirectory)
        return AppDependencies(
            engine: engine,
            clipboard: LiveClipboard(.general),
            sleep: liveSleep,
            announce: LiveAnnouncer.announce,
            panels: LiveFilePanels(),
            files: .live,
            commands: LiveCommandRunner.run,
            preferences: LivePreferences.standard,
            runner: engine,
            systemProxy: SystemProxy.shared,
            onTerminate: LiveAppLifecycle.onTerminate,
            sender: engine,
            workspace: LiveWorkspaceOpener(),
            paths: SupportPaths(directory: WatcherPaths.supportDirectory),
            focusFilterField: LiveSearchFocus.focusFilterField,
            devices: .live
        )
    }

    /// Previews: a throwaway directory and a private pasteboard, so nothing reaches the user's settings or clipboard.
    static func preview() -> AppDependencies {
        let name = "watcher-preview-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let clipboard = LiveClipboard(NSPasteboard(name: .init(name)))
        let engine = makeEngine(in: directory)
        return AppDependencies(
            engine: engine,
            clipboard: clipboard,
            sleep: liveSleep,
            announce: { _ in },
            panels: LiveFilePanels(),
            files: .live,
            commands: LiveCommandRunner.run,
            preferences: LivePreferences.standard,
            runner: engine,
            systemProxy: InertSystemProxy(),
            onTerminate: { _ in },
            sender: engine,
            workspace: LiveWorkspaceOpener(),
            paths: SupportPaths(directory: directory),
            focusFilterField: {},
            devices: .none
        )
    }

    private static func makeEngine(in directory: URL) -> WatcherEngine {
        do { return try WatcherEngine(directory: directory) } catch {
            fatalError("Cannot prepare \(directory.path): \(error)")
        }
    }
}
