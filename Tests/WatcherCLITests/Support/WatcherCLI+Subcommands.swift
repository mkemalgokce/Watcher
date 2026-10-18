import ArgumentParser
@testable import watcher_cli

extension WatcherCLI {
    /// Every subcommand's name on the command line, with the type that runs it.
    static let subcommands: [(name: String, type: String)] = [
        ("start", "Start"), ("mcp", "Mcp"), ("cert", "Cert"), ("install-simulator-cert", "SimulatorCert"),
        ("android", "AndroidCommand"), ("tool", "Tool"), ("rules", "Rules"), ("proxy", "SystemProxyCommand"),
    ]

    static var subcommandNames: [String] {
        subcommands.map(\.name)
    }

    /// Dotted paths such as `rules.export` of every command below a group command, the ones `subcommandNames` only lists.
    static var leafCommandPaths: [String] {
        leaves(under: configuration.subcommands, prefix: "", nested: false).map(\.path)
    }

    static func leafCommand(atPath path: String) -> ParsableCommand.Type? {
        leaves(under: configuration.subcommands, prefix: "", nested: false).first { $0.path == path }?.type
    }

    private static func leaves(
        under commands: [ParsableCommand.Type], prefix: String, nested: Bool
    ) -> [(path: String, type: ParsableCommand.Type)] {
        commands.flatMap { command -> [(path: String, type: ParsableCommand.Type)] in
            let name = command.configuration.commandName ?? String(describing: command).lowercased()
            let path = prefix.isEmpty ? name : "\(prefix).\(name)"
            let children = command.configuration.subcommands
            return children.isEmpty
                ? (nested ? [(path, command)] : [])
                : leaves(under: children, prefix: path, nested: true)
        }
    }

    static func subcommandType(named name: String) -> ParsableCommand.Type? {
        let type = subcommands.first { $0.name == name }?.type
        return configuration.subcommands.first { String(describing: $0) == type }
    }
}
