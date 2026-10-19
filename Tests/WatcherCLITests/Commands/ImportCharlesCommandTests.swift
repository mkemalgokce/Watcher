import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ImportCharlesCommandTests {
    private static let export = """
    <?xml version='1.0' encoding='UTF-8' ?>
    <?charles serialisation-version='2.0' ?>
    <configuration>
      <toolConfiguration>
        <configs>
          <entry>
            <string>Breakpoints</string>
            <breakpoints>
              <toolEnabled>true</toolEnabled>
              <breakpoints>
                <breakpoint>
                  <location>
                    <protocol>https</protocol><host>login.example.com</host><port>443</port><path>/token</path>
                  </location>
                  <method>POST</method>
                  <request>true</request>
                </breakpoint>
              </breakpoints>
            </breakpoints>
          </entry>
          <entry>
            <string>Reverse Proxies</string>
            <reverseProxies>
              <reverseProxies>
                <reverseProxy>
                  <sourcePort>18888</sourcePort><destPort>443</destPort><destHost>api.example.com</destHost>
                </reverseProxy>
              </reverseProxies>
            </reverseProxies>
          </entry>
        </configs>
      </toolConfiguration>
    </configuration>
    """

    private static let summary = "[Import] Charles settings from /tmp/charles.xml: block 0, allow 0, map local 0, "
        + "map remote 0, breakpoints 1, DNS 0, reverse proxies 1"

    @Test(arguments: [(["charles.xml"], "append"), (["charles.xml", "--mode", "override"], "override")])
    func modeDefaultsToAppend(arguments: [String], mode: String) throws {
        let command = try ImportCharles.parse(arguments)
        #expect(command.path == "charles.xml")
        #expect(command.mode.rawValue == mode)
    }

    @Test
    func appendAddsTheRulesAndCountsThem() throws {
        let cli = try harnessWithOneStoredBreakpoint()
        try ImportCharles.parse(["/tmp/charles.xml"]).run(in: cli.environment)
        let settings = cli.environment.settings.value
        #expect(settings.breakpoints.rules.count == 2)
        #expect(settings.reverseProxy.rules.count == 1)
        #expect(cli.printed == [Self.summary])
    }

    @Test
    func overrideReplacesTheToolRulesButKeepsPortAndSSLSettings() throws {
        let cli = try harnessWithOneStoredBreakpoint()
        try ImportCharles.parse(["/tmp/charles.xml", "--mode", "override"]).run(in: cli.environment)
        let settings = cli.environment.settings.value
        #expect(settings.breakpoints.rules.count == 1)
        #expect(settings.breakpoints.rules.first?.matching.pattern != "mine.test/*")
        #expect(settings.port == 7777)
        #expect(settings.sslProxying.include == ["*.mine.test"])
    }

    @Test(arguments: ["bogus", "", "Append"])
    func anUnknownModeIsRejectedWhenParsing(mode: String) {
        #expect(throws: (any Error).self) { try ImportCharles.parse(["/tmp/missing.xml", "--mode", mode]) }
    }

    @Test
    func aMissingFileChangesNothing() throws {
        let cli = CLIHarness()
        let command = try ImportCharles.parse(["/tmp/missing.xml"])
        #expect(throws: CocoaError.self) { try command.run(in: cli.environment) }
        #expect(!cli.files.paths.contains(cli.supportFile("settings.json")))
        #expect(cli.printed.isEmpty)
    }

    private func harnessWithOneStoredBreakpoint() throws -> CLIHarness {
        let cli = CLIHarness()
        var settings = WatcherSettings()
        settings.port = 7777
        settings.sslProxying.include = ["*.mine.test"]
        settings.breakpoints.rules = [BreakpointRule(matching: MatchingRule(pattern: "mine.test/*"))]
        try cli.environment.settings.replace(with: settings)
        cli.files.write(Data(Self.export.utf8), to: "/tmp/charles.xml")
        return cli
    }

    @Test(arguments: ["not xml at all", "<configuration><unclosed>"])
    func aFileThatIsNotXMLChangesNothingAndPrintsNothing(content: String) throws {
        let cli = CLIHarness()
        cli.files.write(Data(content.utf8), to: "/tmp/charles.xml")
        let command = try ImportCharles.parse(["/tmp/charles.xml"])
        #expect(throws: CharlesSettings.ImportError.self) { try command.run(in: cli.environment) }
        #expect(!cli.files.paths.contains(cli.supportFile("settings.json")))
        #expect(cli.printed.isEmpty)
    }

    @Test
    func aSettingsFileThatCannotBeWrittenPrintsNoSummary() throws {
        let cli = try harnessWithOneStoredBreakpoint()
        cli.files.fail(.writePrivately)
        let command = try ImportCharles.parse(["/tmp/charles.xml"])
        #expect(throws: FileAccessFake.Failure(operation: .writePrivately)) { try command.run(in: cli.environment) }
        #expect(cli.printed.isEmpty)
    }
}
