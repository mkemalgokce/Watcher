import Foundation
import WatcherCore

extension CLIEnvironment {
    /// The real terminal, disk, programs and network interfaces.
    static let live = CLIEnvironment(
        // The throwing write: the older one raises an uncatchable exception once a closed terminal fails it.
        output: { try? FileHandle.standardOutput.write(contentsOf: Data("\($0)\n".utf8)) },
        errorOutput: { try? FileHandle.standardError.write(contentsOf: Data("\($0)\n".utf8)) },
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
