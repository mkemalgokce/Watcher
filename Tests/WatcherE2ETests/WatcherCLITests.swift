import Foundation
import Testing
import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.e2e))
struct WatcherCLITests {
    @Test
    func helpListsEverySubcommandAndSucceeds() throws {
        let home = try TemporaryDirectory(prefix: "watcher-e2e")
        let help = try WatcherCLIRun.run(["--help"], home: home.url)
        #expect(help.status == 0)
        for name in ["start", "mcp", "cert", "install-simulator-cert", "android", "tool", "rules", "proxy"] {
            #expect(help.text.contains(name), "\(name) missing from: \(help.text)")
        }
    }

    @Test(arguments: [["bogus"], ["tool", "teleport", "on"], ["proxy", "sideways"]])
    func anUnknownArgumentFailsWithTheUsageExitCode(arguments: [String]) throws {
        let home = try TemporaryDirectory(prefix: "watcher-e2e")
        let result = try WatcherCLIRun.run(arguments, home: home.url)
        #expect(result.status == 64)
        #expect(!FileManager.default.fileExists(atPath: home.appending("settings.json").path))
    }

    @Test
    func certCreatesTheRootCertificateInWatcherHomeAndPrintsItsPath() throws {
        let home = try TemporaryDirectory(prefix: "watcher-e2e")
        let cert = try WatcherCLIRun.run(["cert"], home: home.url)
        let path = home.appending("watcher-ca.pem").path
        #expect(cert.status == 0)
        #expect(cert.text == "\(path)\n")
        #expect(try String(contentsOfFile: path, encoding: .utf8).hasPrefix("-----BEGIN CERTIFICATE-----"))
    }

    /// A closed terminal makes every write fail; the command must still finish its work instead of crashing.
    @Test
    func anOutputThatCannotBeWrittenDoesNotStopTheCommand() async throws {
        let home = try TemporaryDirectory(prefix: "watcher-e2e")
        let process = Process()
        process.executableURL = try WatcherCLIBinary.locate()
        process.arguments = ["cert"]
        process.environment = ProcessInfo.processInfo.environment.merging(["WATCHER_HOME": home.url.path]) { $1 }
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

    @Test
    func aToolSwitchedOnIsInTheExportedRules() throws {
        let home = try TemporaryDirectory(prefix: "watcher-e2e")
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

    @Test
    func rulesExportedFromOneHomeImportIntoAnother() throws {
        let source = try TemporaryDirectory(prefix: "watcher-e2e")
        let destination = try TemporaryDirectory(prefix: "watcher-e2e")
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

    @Test
    func anImportWithAnUnknownModeFailsAndChangesNothing() throws {
        let home = try TemporaryDirectory(prefix: "watcher-e2e")
        let rules = home.appending("rules.json")
        _ = try WatcherCLIRun.run(["tool", "no-caching", "on"], home: home.url)
        _ = try WatcherCLIRun.run(["rules", "export", rules.path], home: home.url)
        let before = try Data(contentsOf: home.appending("settings.json"))

        let result = try WatcherCLIRun.run(["rules", "import", rules.path, "--mode", "bogus"], home: home.url)

        #expect(result.status == 64)
        #expect(try Data(contentsOf: home.appending("settings.json")) == before)
    }
}
