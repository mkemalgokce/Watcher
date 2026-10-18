import ArgumentParser
import SnapshotTesting
import Testing
@testable import watcher_cli

/// The help text is the command line's contract: a renamed option, a lost default or a changed abstract shows in review.
@Suite(.tags(.unit))
struct HelpSnapshotTests {
    @Test
    func theRootHelp() {
        assertSnapshot(of: WatcherCLI.helpMessage(columns: 100), as: .lines)
    }

    @Test(arguments: WatcherCLI.subcommandNames)
    func eachSubcommandsHelp(name: String) throws {
        let command = try #require(WatcherCLI.subcommandType(named: name))
        assertSnapshot(of: WatcherCLI.helpMessage(for: command, columns: 100), as: .lines, named: name)
    }
}
