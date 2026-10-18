import AppKit
import WatcherCore

extension AppDependencies {
    /// The real app: ~/.watcher and the general pasteboard.
    static func live() -> AppDependencies {
        AppDependencies(
            engine: makeEngine(in: WatcherPaths.supportDirectory),
            clipboard: LiveClipboard(.general),
            sleep: liveSleep,
            announce: LiveAnnouncer.announce,
            panels: LiveFilePanels(),
            files: .live,
            commands: LiveCommandRunner.run,
            preferences: LivePreferences.standard
        )
    }

    /// Previews: a throwaway directory and a private pasteboard, so nothing reaches the user's settings or clipboard.
    static func preview() -> AppDependencies {
        let name = "watcher-preview-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let clipboard = LiveClipboard(NSPasteboard(name: .init(name)))
        return AppDependencies(
            engine: makeEngine(in: directory),
            clipboard: clipboard,
            sleep: liveSleep,
            announce: { _ in },
            panels: LiveFilePanels(),
            files: .live,
            commands: LiveCommandRunner.run,
            preferences: LivePreferences.standard
        )
    }

    private static func makeEngine(in directory: URL) -> WatcherEngine {
        do { return try WatcherEngine(directory: directory) } catch {
            fatalError("Cannot prepare \(directory.path): \(error)")
        }
    }
}
