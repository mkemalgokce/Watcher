import Foundation
@testable import watcher_cli
@testable import WatcherCore
import WatcherTestSupport

/// A `CLIEnvironment` over an in-memory file system, a command spy and an engine fake, whose output the test reads back.
/// The support folder is `/fake-home/.watcher`, as `WATCHER_HOME` names it; standard input answers `input` line by line.
final class CLIHarness {
    static let supportDirectory = "/fake-home/.watcher"

    let files: FileAccessFake
    let commands: CommandRunnerSpy
    let engine: EngineFake
    let shutdown: ShutdownTrigger
    private let lines = LockedBox<[String]>([])
    private let errorLines = LockedBox<[String]>([])
    private let input: LockedBox<[String]>
    private let lanAddresses: [LocalNetwork.Address]

    init(
        files: FileAccessFake = FileAccessFake(),
        commands: CommandRunnerSpy = CommandRunnerSpy(),
        lanAddresses: [LocalNetwork.Address] = [],
        input: [String] = [],
        shutdown: ShutdownTrigger = ShutdownTrigger(),
        engine: ((SettingsStore) -> EngineFake)? = nil
    ) {
        self.files = files; self.commands = commands; self.lanAddresses = lanAddresses; self.shutdown = shutdown
        self.input = LockedBox(input)
        let settings = SettingsStore(
            url: WatcherPaths.settingsFile(in: URL(fileURLWithPath: Self.supportDirectory)),
            files: files.access
        )
        self.engine = engine?(settings) ?? EngineFake(settings: settings)
    }

    /// Standard output, line by line.
    var printed: [String] {
        lines.value
    }

    /// Standard error, line by line.
    var printedToErrorOutput: [String] {
        errorLines.value
    }

    var environment: CLIEnvironment {
        CLIEnvironment(
            output: { [lines] line in lines.mutate { $0.append(line) } },
            errorOutput: { [errorLines] line in errorLines.mutate { $0.append(line) } },
            readLine: { [input] in
                var line: String?
                input.mutate {
                    if !$0.isEmpty {
                        line = $0.removeFirst()
                    }
                }
                return line
            },
            variables: ["WATCHER_HOME": Self.supportDirectory],
            home: URL(fileURLWithPath: "/Users/me", isDirectory: true),
            files: files.access,
            commands: commands.runner,
            lanAddresses: { [lanAddresses] in lanAddresses },
            makeEngine: { [engine] _ in engine },
            shutdownSignal: shutdown.signal,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func supportFile(_ name: String) -> String {
        "\(Self.supportDirectory)/\(name)"
    }
}
