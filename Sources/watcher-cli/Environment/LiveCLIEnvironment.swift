import Foundation
import WatcherCore

extension CLIEnvironment {
    /// The real terminal, disk, programs and network interfaces.
    static let live = CLIEnvironment(
        output: { FileHandle.standardOutput.write(Data("\($0)\n".utf8)) },
        errorOutput: { FileHandle.standardError.write(Data("\($0)\n".utf8)) },
        readLine: { Swift.readLine(strippingNewline: true) },
        variables: ProcessInfo.processInfo.environment,
        home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        files: .live,
        commands: LiveCommandRunner.run,
        lanAddresses: { LocalNetwork.ipv4Addresses() },
        makeEngine: { try WatcherEngine(directory: $0) },
        shutdownSignal: LiveShutdownSignal.stopRequest,
        now: { Date() }
    )
}
