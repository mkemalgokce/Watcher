import Foundation
import WatcherCore

extension CLIEnvironment {
    /// The real terminal, disk, programs and network interfaces.
    static let live = CLIEnvironment(
        output: { FileHandle.standardOutput.write(Data("\($0)\n".utf8)) },
        variables: ProcessInfo.processInfo.environment,
        home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        files: .live,
        commands: LiveCommandRunner.run,
        lanAddresses: { LocalNetwork.ipv4Addresses() },
        now: { Date() }
    )
}
