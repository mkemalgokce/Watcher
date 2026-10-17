import ArgumentParser

@main
struct WatcherCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watcher-cli",
        abstract: "Capture and debug HTTP(S) traffic from the terminal.",
        subcommands: [Start.self, Mcp.self, Cert.self, SimulatorCert.self, AndroidCommand.self, Tool.self, Rules.self, SystemProxyCommand.self],
        defaultSubcommand: Start.self
    )
}
