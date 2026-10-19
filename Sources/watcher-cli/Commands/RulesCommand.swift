import ArgumentParser
import Foundation
import WatcherCore

extension WatcherSettings.ExportMode: ExpressibleByArgument {}

struct Rules: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export or import every tool's rules as one JSON file.",
        subcommands: [Export.self, Import.self, ImportCharles.self]
    )

    struct Export: ParsableCommand {
        @Argument(help: "Destination file.") var path: String
        @Option(help: "all (every rule) or enabledRules (only enabled ones).")
        var mode: WatcherSettings.ExportMode = .all

        func run() throws {
            try run(in: .live)
        }

        func run(in environment: CLIEnvironment) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let destination = environment.url(forPath: path)
            environment.output(
                "[Export] Prepare for exporting Watcher Rules. Mode = \(mode.rawValue), output = \(destination.path)"
            )
            let rules = try encoder.encode(environment.settings.value.exported(mode))
            try environment.files.writeAtomically(rules, destination)
        }
    }

    struct Import: ParsableCommand {
        @Argument(help: "JSON file produced by `rules export`.") var path: String
        @Option(help: "append (add to existing rules) or override (replace everything).")
        var mode: WatcherSettings.ImportMode = .override

        func run() throws {
            try run(in: .live)
        }

        func run(in environment: CLIEnvironment) throws {
            let source = environment.url(forPath: path)
            environment.output(
                "[Import] Prepare for importing Watcher Rules. Mode = \(mode.rawValue), input = \(source.path)"
            )
            let data = try environment.files.read(source)
            let incoming = try JSONDecoder().decode(WatcherSettings.self, from: data)
            let store = environment.settings
            try store.replace(with: store.value.importing(incoming, mode: mode))
            environment.output("Imported")
        }
    }
}
