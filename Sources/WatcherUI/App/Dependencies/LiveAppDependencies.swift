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
            previews: { [engine] in await engine.previews(for: $0) },
            workspace: LiveWorkspaceOpener(),
            paths: SupportPaths(directory: WatcherPaths.supportDirectory),
            focusFilterField: LiveSearchFocus.focusFilterField,
            devices: .live,
            loginItem: .live,
            now: Date.init,
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory()),
            appInfo: .live,
            faviconDownload: LiveFaviconDownload.fetch
        )
    }

    /// Previews: a throwaway directory, a private pasteboard and preferences in memory, so nothing reaches the user's
    /// settings, defaults or clipboard.
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
            preferences: InMemoryPreferences(),
            runner: engine,
            systemProxy: InertSystemProxy(),
            onTerminate: { _ in },
            sender: engine,
            previews: { [engine] in await engine.previews(for: $0) },
            workspace: LiveWorkspaceOpener(),
            paths: SupportPaths(directory: directory),
            focusFilterField: {},
            devices: .none,
            loginItem: .inert,
            now: Date.init,
            homeDirectory: URL(fileURLWithPath: NSHomeDirectory()),
            appInfo: .live,
            faviconDownload: LiveFaviconDownload.fetch
        )
    }

    private static func makeEngine(in directory: URL) -> WatcherEngine {
        do { return try WatcherEngine(directory: directory) } catch {
            fatalError("Cannot prepare \(directory.path): \(error)")
        }
    }
}
