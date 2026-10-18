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

    static func subcommandType(named name: String) -> ParsableCommand.Type? {
        let type = subcommands.first { $0.name == name }?.type
        return configuration.subcommands.first { String(describing: $0) == type }
    }
}
