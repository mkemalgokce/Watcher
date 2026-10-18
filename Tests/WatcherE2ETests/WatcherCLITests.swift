import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.e2e))
struct WatcherCLITests {
    @Test
    func helpListsEverySubcommandAndSucceeds() throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let help = try WatcherCLIRun.run(["--help"], home: home.url)
            #expect(help.status == 0)
            let names = WatcherCLI.configuration.subcommands.map {
                $0.configuration.commandName ?? String(describing: $0).lowercased()
            }
            #expect(names.contains("rules"))
            for name in names {
                #expect(help.text.contains(name), "\(name) missing from: \(help.text)")
            }
        }
    }

    @Test(arguments: [["bogus"], ["tool", "teleport", "on"], ["proxy", "sideways"]])
    func anUnknownArgumentFailsWithTheUsageExitCode(arguments: [String]) throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let result = try WatcherCLIRun.run(arguments, home: home.url)
            #expect(result.status == 64)
            #expect(!FileManager.default.fileExists(atPath: home.appending("settings.json").path))
        }
    }

    @Test
    func certCreatesTheRootCertificateInWatcherHomeAndPrintsItsPath() throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let cert = try WatcherCLIRun.run(["cert"], home: home.url)
            let path = home.appending("watcher-ca.pem").path
            #expect(cert.status == 0)
            #expect(cert.text == "\(path)\n")
            #expect(try String(contentsOfFile: path, encoding: .utf8).hasPrefix("-----BEGIN CERTIFICATE-----"))
        }
    }

    /// A closed terminal makes every write fail; the command must still finish its work instead of crashing.
    @Test
    func anOutputThatCannotBeWrittenDoesNotStopTheCommand() async throws {
        try await withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let process = Process()
            process.executableURL = try WatcherCLIBinary.locate()
            process.arguments = ["cert"]
            process.environment = WatcherCLIBinary.environment(home: home.url)
            let unwritable = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null"))
            process.standardOutput = unwritable
            process.standardError = unwritable

            try process.run()
            let exited = await eventually(timeout: 30) { !process.isRunning }
            if !exited {
                process.terminate()
            }
            try #require(exited, "watcher-cli cert did not exit within 30 s with an unwritable output")

            #expect(process.terminationReason == .exit)
            #expect(process.terminationStatus == 0)
            #expect(FileManager.default.fileExists(atPath: home.appending("watcher-ca.pem").path))
        }
    }

    @Test
    func aToolSwitchedOnIsInTheExportedRules() throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let rules = home.appending("rules.json")

            let tool = try WatcherCLIRun.run(["tool", "map-local", "on"], home: home.url)
            let export = try WatcherCLIRun.run(["rules", "export", rules.path], home: home.url)

            #expect(tool.status == 0)
            #expect(tool.text == "map-local: on\n")
            #expect(export.status == 0)
            let exported = try JSONDecoder().decode(WatcherSettings.self, from: Data(contentsOf: rules))
            #expect(exported.mapLocal.isEnabled)
            #expect(!exported.mapRemote.isEnabled)
        }
    }

    @Test
    func rulesExportedFromOneHomeImportIntoAnother() throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { source in
            try withTemporaryDirectory(prefix: "watcher-e2e") { destination in
                let rules = source.appending("rules.json")
                _ = try WatcherCLIRun.run(["tool", "no-caching", "on"], home: source.url)
                _ = try WatcherCLIRun.run(["rules", "export", rules.path], home: source.url)

                let imported = try WatcherCLIRun.run(["rules", "import", rules.path], home: destination.url)

                #expect(imported.status == 0)
                #expect(imported.text.hasSuffix("Imported\n"))
                let settings = try JSONDecoder().decode(
                    WatcherSettings.self,
                    from: Data(contentsOf: destination.appending("settings.json"))
                )
                #expect(settings.noCaching)
            }
        }
    }

    @Test
    func anImportWithAnUnknownModeFailsAndChangesNothing() throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let rules = home.appending("rules.json")
            _ = try WatcherCLIRun.run(["tool", "no-caching", "on"], home: home.url)
            _ = try WatcherCLIRun.run(["rules", "export", rules.path], home: home.url)
            let before = try Data(contentsOf: home.appending("settings.json"))

            let result = try WatcherCLIRun.run(["rules", "import", rules.path, "--mode", "bogus"], home: home.url)

            #expect(result.status == 64)
            #expect(try Data(contentsOf: home.appending("settings.json")) == before)
        }
    }
}
