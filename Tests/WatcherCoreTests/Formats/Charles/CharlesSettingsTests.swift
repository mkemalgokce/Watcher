import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// Settings exactly as Charles Proxy 5.2.2 wrote them after loading and re-saving a configuration
/// (`charles --headless --config`), so every tag, order and omitted default below is Charles' own.
private let realExport = """
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
                <protocol>https</protocol>
                <host>login.example.com</host>
                <port>443</port>
                <path>/token</path>
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
              <sourcePort>18888</sourcePort>
              <destPort>443</destPort>
              <destHost>api.example.com</destHost>
              <preserveHostHeader>true</preserveHostHeader>
            </reverseProxy>
          </reverseProxies>
        </reverseProxies>
      </entry>
      <entry>
        <string>Block List</string>
        <blacklist>
          <locations>
            <locationPatterns>
              <locationMatch>
                <location>
                  <protocol>https</protocol>
                  <host>ads.example.com</host>
                  <port>443</port>
                  <path>/*</path>
                </location>
              </locationMatch>
              <locationMatch>
                <enabled>false</enabled>
                <location>
                  <protocol>https</protocol>
                  <host>off.example.com</host>
                  <port>443</port>
                </location>
              </locationMatch>
            </locationPatterns>
          </locations>
          <toolEnabled>true</toolEnabled>
        </blacklist>
      </entry>
      <entry>
        <string>Map Remote</string>
        <map>
          <toolEnabled>true</toolEnabled>
          <mappings>
            <mapMapping>
              <sourceLocation>
                <protocol>https</protocol>
                <host>old.example.com</host>
                <port>443</port>
                <path>/v1/*</path>
              </sourceLocation>
              <destLocation>
                <protocol>https</protocol>
                <host>new.example.com</host>
                <port>8443</port>
                <path>/v2/x</path>
                <query>a=1</query>
              </destLocation>
              <preserveHostHeader>true</preserveHostHeader>
            </mapMapping>
          </mappings>
        </map>
      </entry>
      <entry>
        <string>Map Local</string>
        <mapLocal>
          <toolEnabled>true</toolEnabled>
          <mappings>
            <mapLocalMapping>
              <sourceLocation>
                <protocol>https</protocol>
                <host>api.example.com</host>
                <port>443</port>
                <path>/v1/users</path>
              </sourceLocation>
              <dest>/tmp/users.json</dest>
            </mapLocalMapping>
            <mapLocalMapping>
              <sourceLocation>
                <host>static.example.com</host>
                <path>/assets/*</path>
              </sourceLocation>
              <dest>/tmp</dest>
              <enabled>false</enabled>
            </mapLocalMapping>
          </mappings>
        </mapLocal>
      </entry>
      <entry>
        <string>Allow List</string>
        <whitelist>
          <locations>
            <locationPatterns>
              <locationMatch>
                <location>
                  <protocol>http</protocol>
                  <host>*.corp.test</host>
                  <port>8080</port>
                </location>
              </locationMatch>
            </locationPatterns>
          </locations>
        </whitelist>
      </entry>
      <entry>
        <string>No Caching</string>
        <selectedHostsTool />
      </entry>
      <entry>
        <string>DNS Spoofing</string>
        <dnsSpoofing>
          <toolEnabled>true</toolEnabled>
          <spoofs>
            <dnsSpoof>
              <name>dev.example.com</name>
              <address>127.0.0.1</address>
            </dnsSpoof>
          </spoofs>
        </dnsSpoofing>
      </entry>
    </configs>
  </toolConfiguration>
</configuration>
"""

@Suite(.tags(.unit))
struct CharlesSettingsTests {
    private let imported: WatcherSettings

    init() throws {
        imported = try CharlesSettings.importSettings(from: Data(realExport.utf8))
    }

    @Test
    func blockAndAllowListsKeepPerEntryFlagsAndToolSwitch() throws {
        #expect(imported.blockList.isEnabled)
        #expect(imported.blockList.rules.map(\.isEnabled) == [true, false], "the second match carries enabled=false")
        let ads = try #require(imported.blockList.rules.first).matching.compile()
        #expect(
            ads.matches(.fixture(host: "ads.example.com", path: "/banner.gif")),
            "Charles writes <port>443</port>; it must not break matching"
        )
        #expect(!ads.matches(.fixture(host: "example.com", path: "/")))

        #expect(!imported.allowList.isEnabled, "Charles omits toolEnabled when it is false")
        let corp = try #require(imported.allowList.rules.first).matching.compile()
        #expect(corp.matches(.fixture(scheme: "http", host: "api.corp.test", port: 8080, path: "/x")))
        #expect(
            !corp.matches(.fixture(scheme: "http", host: "api.corp.test", port: 80, path: "/x")),
            "a non-default port stays in the pattern"
        )
    }

    @Test
    func mapLocalKeepsFileDirectoryAndDisabledEntries() {
        let local = imported.mapLocal
        #expect(local.isEnabled)
        #expect(
            local.rules.map(\.source) == [.file("/tmp/users.json"), .directory("/tmp")],
            "an existing folder becomes a directory mapping"
        )
        #expect(local.rules.map(\.isEnabled) == [true, false])
        #expect(local.rules[0].matching.compile().matches(.fixture(host: "api.example.com", path: "/v1/users")))
    }

    @Test
    func mapRemoteKeepsDestinationAndPreserveHostHeader() throws {
        let remote = try #require(imported.mapRemote.rules.first)
        #expect(
            remote.destination
                == .init(scheme: "https", host: "new.example.com", port: 8443, path: "/v2/x", query: "a=1")
        )
        #expect(remote.preserveHostHeader)
        #expect(remote.matching.compile().matches(.fixture(host: "old.example.com", path: "/v1/things")))
    }

    @Test
    func breakpointsDNSSpoofingAndReverseProxyAreImported() throws {
        let breakpoint = try #require(imported.breakpoints.rules.first)
        #expect(breakpoint.onRequest); #expect(!breakpoint.onResponse, "Charles omits response=false")
        let token = RequestRecord.fixture(method: "POST", host: "login.example.com", path: "/token")
        #expect(breakpoint.matching.compile().matches(token))
        #expect(
            !breakpoint.matching.compile().matches(.fixture(host: "login.example.com", path: "/token")),
            "method=POST is kept"
        )

        #expect(imported.dnsSpoofing.rules == [DNSSpoofRule(host: "dev.example.com", address: "127.0.0.1")])

        let reverse = try #require(imported.reverseProxy.rules.first)
        let ports = [reverse.localPort, reverse.remotePort]
        #expect(ports == [18888, 443])
        #expect(reverse.remoteHost == "api.example.com")
        #expect(reverse.preserveHost && reverse.forceTLS)
    }

    @Test
    func importingOverToolRulesKeepsEverythingElse() {
        var current = WatcherSettings()
        current.port = 7777; current.socks = SocksSettings(isEnabled: true, port: 9999)
        current.sslProxying.exclude = ["pinned.test"]
        current.blockList = RuleSet(
            isEnabled: true,
            rules: [BlockRule(name: "old", matching: MatchingRule(pattern: "old"))]
        )
        let merged = current.replacingToolRules(with: imported)
        #expect(merged.blockList.rules.map(\.name) == ["Charles", "Charles"], "the tool rules are replaced")
        let ports = [merged.port, merged.socks.port]
        #expect(ports == [7777, 9999])
        #expect(merged.sslProxying.exclude == ["pinned.test"])
    }

    @Test
    func anEmptyReverseProxyToolStaysOff() throws {
        let empty = try CharlesSettings.importSettings(
            from: configuration(entry: "Reverse Proxies", "<reverseProxies />")
        )
        #expect(!empty.reverseProxy.isEnabled)
    }

    @Test
    func anEmptyToolTakesDefaultsAndNonXMLIsRefused() throws {
        let empty = try CharlesSettings.importSettings(from: configuration(entry: "Block List", "<blacklist />"))
        #expect(!empty.blockList.isEnabled); #expect(empty.blockList.rules.isEmpty)
        #expect(throws: (any Error).self) { try CharlesSettings.importSettings(from: Data("not xml <<<".utf8)) }
    }

    private func configuration(entry name: String, _ tool: String) -> Data {
        Data((
            "<configuration><toolConfiguration><configs><entry><string>\(name)</string>\(tool)</entry></configs>"
                + "</toolConfiguration></configuration>"
        ).utf8)
    }
}
