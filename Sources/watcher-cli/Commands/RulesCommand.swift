import ArgumentParser
import Foundation
import WatcherCore

struct Rules: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export or import every tool's rules as one JSON file.",
        subcommands: [Export.self, Import.self, ImportCharles.self]
    )

    private static var store: SettingsStore {
        SettingsStore(url: WatcherPaths.supportDirectory.appendingPathComponent("settings.json"))
    }

    struct Export: ParsableCommand {
        @Argument(help: "Destination file.") var path: String
        @Option(help: "all (every rule) or enabledRules (only enabled ones).") var mode = "all"

        func run() throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let exportMode = WatcherSettings.ExportMode(rawValue: mode) else { throw ValidationError("mode must be all or enabledRules") }
            let destination = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            print("[Export] Prepare for exporting Watcher Rules. Mode = \(mode), output = \(destination.path)")
            try encoder.encode(Rules.store.value.exported(exportMode)).write(to: destination, options: .atomic)
        }
    }

    struct Import: ParsableCommand {
        @Argument(help: "JSON file produced by `rules export`.") var path: String
        @Option(help: "append (add to existing rules) or override (replace everything).") var mode = "override"

        func run() throws {
            let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            print("[Import] Prepare for importing Watcher Rules. Mode = \(mode), input = \(source.path)")
            let data = try Data(contentsOf: source)
            guard let importMode = WatcherSettings.ImportMode(rawValue: mode) else { throw ValidationError("mode must be append or override") }
            let incoming = try JSONDecoder().decode(WatcherSettings.self, from: data)
            try Rules.store.replace(with: Rules.store.value.importing(incoming, mode: importMode))
            print("Imported")
        }
    }
}
