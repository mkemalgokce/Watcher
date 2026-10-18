import Foundation
@testable import watcher_cli
@testable import WatcherCore
import WatcherTestSupport

/// A `CLIEnvironment` over an in-memory file system and a command spy, whose output the test reads back.
/// The support folder is `/fake-home/.watcher`, as `WATCHER_HOME` names it.
final class CLIHarness {
    static let supportDirectory = "/fake-home/.watcher"

    let files: FileAccessFake
    let commands: CommandRunnerSpy
    private let lines = LockedBox<[String]>([])
    private let lanAddresses: [LocalNetwork.Address]

    init(
        files: FileAccessFake = FileAccessFake(),
        commands: CommandRunnerSpy = CommandRunnerSpy(),
        lanAddresses: [LocalNetwork.Address] = []
    ) {
        self.files = files; self.commands = commands; self.lanAddresses = lanAddresses
    }

    var printed: [String] {
        lines.value
    }

    var environment: CLIEnvironment {
        CLIEnvironment(
            output: { [lines] line in lines.mutate { $0.append(line) } },
            variables: ["WATCHER_HOME": Self.supportDirectory],
            home: URL(fileURLWithPath: "/Users/me", isDirectory: true),
            files: files.access,
            commands: commands.runner,
            lanAddresses: { [lanAddresses] in lanAddresses },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func supportFile(_ name: String) -> String {
        "\(Self.supportDirectory)/\(name)"
    }
}
