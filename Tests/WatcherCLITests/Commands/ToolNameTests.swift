import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ToolNameTests {
    private static let switches: [(ToolName, WritableKeyPath<WatcherSettings, Bool>)] = [
        (.breakpoint, \.breakpoints.isEnabled), (.mapLocal, \.mapLocal.isEnabled), (.mapRemote, \.mapRemote.isEnabled),
        (.scripting, \.scripting.isEnabled), (.blockList, \.blockList.isEnabled), (.allowList, \.allowList.isEnabled),
        (.reverseProxy, \.reverseProxy.isEnabled), (.networkCondition, \.throttle.isEnabled), (.noCaching, \.noCaching),
        (.dnsSpoofing, \.dnsSpoofing.isEnabled), (.externalProxy, \.externalProxy.isEnabled),
    ]

    @Test
    func namesAreTheDocumentedKebabCaseWords() {
        let names = ToolName.allCases.map(\.rawValue)
        #expect(names == [
            "breakpoint", "map-local", "map-remote", "scripting", "block-list", "allow-list", "reverse-proxy",
            "network-condition", "no-caching", "dns-spoofing", "external-proxy",
        ])
    }

    @Test
    func everyToolHasASwitch() {
        #expect(Set(Self.switches.map(\.0.rawValue)) == Set(ToolName.allCases.map(\.rawValue)))
    }

    @Test(arguments: ToolName.allCases)
    func switchingOnFlipsOnlyThatToolAndSwitchingOffRestoresIt(tool: ToolName) throws {
        let keyPath = try #require(Self.switches.first { $0.0 == tool }?.1)
        var settings = WatcherSettings()
        settings[keyPath: keyPath] = false
        let off = settings

        tool.set(true, in: &settings)
        var expected = off
        expected[keyPath: keyPath] = true
        #expect(settings == expected)

        tool.set(false, in: &settings)
        #expect(settings == off)
    }
}
