import AppKit
import WatcherCore

extension AppDependencies {
    /// The real app: ~/.watcher and the general pasteboard.
    static func live() -> AppDependencies {
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString)")
        let opened = openEngine(in: WatcherPaths.supportDirectory, fallback: fallback)
        let engine = opened.engine
        return AppDependencies(
            engine: engine,
            startupProblem: opened.problem,
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
            paths: SupportPaths(directory: opened.directory),
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
        return preview(in: FileManager.default.temporaryDirectory.appendingPathComponent(name))
    }

    /// The preview wiring over `directory`, which the caller owns and removes; `commands` runs the programs it starts.
    static func preview(
        in directory: URL,
        commands: @escaping CommandRunner = LiveCommandRunner.run
    ) -> AppDependencies {
        let clipboard = LiveClipboard(NSPasteboard(name: .init(directory.lastPathComponent)))
        let engine = makeEngine(in: directory)
        return AppDependencies(
            engine: engine,
            clipboard: clipboard,
            sleep: liveSleep,
            announce: { _ in },
            panels: LiveFilePanels(),
            files: .live,
            commands: commands,
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
            faviconDownload: { _ in nil }
        )
    }

    /// The engine over `directory`; when that cannot be opened (an unreadable settings file or root certificate) one
    /// over `fallback` instead, with the folder it really opened and the reason for the window to show.
    static func openEngine(
        in directory: URL,
        fallback: URL,
        make: (URL) throws -> WatcherEngine = { try WatcherEngine(directory: $0) }
    ) -> OpenedEngine {
        do { return try OpenedEngine(engine: make(directory), directory: directory, problem: nil) } catch {
            let message = "Cannot open Watcher's data in \(directory.path): \(error). "
                + "This session records into a temporary folder; fix the folder and relaunch Watcher."
            let problem = StartupProblem(message: message, folder: directory)
            do { return try OpenedEngine(engine: make(fallback), directory: fallback, problem: problem) } catch {
                fatalError("Cannot prepare \(fallback.path): \(error)")
            }
        }
    }

    struct OpenedEngine {
        let engine: WatcherEngine
        let directory: URL
        let problem: StartupProblem?
    }

    private static func makeEngine(in directory: URL) -> WatcherEngine {
        do { return try WatcherEngine(directory: directory) } catch {
            fatalError("Cannot prepare \(directory.path): \(error)")
        }
    }
}
