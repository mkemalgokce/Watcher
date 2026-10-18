import Testing
@testable import WatcherCore
import WatcherTestSupport

/// Export and append-import must cover every tool's rules, not only the eight the transfer code first listed.
@Suite(.tags(.unit))
struct RuleTransferTests {
    private let match = MatchingRule(pattern: "*")

    /// Settings whose Protobuf, Previewer and Custom Certificate tools hold the given rules, plus non-rule settings.
    private func settings(port: Int, toolsOn: Bool, rules: [(name: String, on: Bool)]) -> WatcherSettings {
        var settings = WatcherSettings()
        settings.port = port
        settings.protobufSchemas = ["\(port).desc"]
        settings.protobuf = RuleSet(isEnabled: toolsOn, rules: rules.map {
            ProtobufRule(name: $0.name, isEnabled: $0.on, matching: match)
        })
        settings.previewers = RuleSet(isEnabled: toolsOn, rules: rules.map {
            PreviewerRule(name: $0.name, isEnabled: $0.on, matching: match)
        })
        settings.customCertificates = RuleSet(isEnabled: toolsOn, rules: rules.map {
            CustomCertificateRule(name: $0.name, isEnabled: $0.on, host: "h", role: .server, p12Path: "p")
        })
        return settings
    }

    @Test
    func enabledRulesExportDropsDisabledProtobufPreviewerAndCertificateRules() {
        let all = settings(port: 1111, toolsOn: true, rules: [("on", true), ("off", false)])
        #expect(all.exported(.enabledRules) == settings(port: 1111, toolsOn: true, rules: [("on", true)]))
        #expect(all.exported(.all) == all)
    }

    @Test
    func enabledRulesExportKeepsSwitchedOffTools() {
        let off = settings(port: 1111, toolsOn: false, rules: [("on", true), ("off", false)])
        #expect(off.exported(.enabledRules) == settings(port: 1111, toolsOn: false, rules: [("on", true)]))
    }

    @Test
    func appendImportAddsProtobufPreviewerAndCertificateRules() {
        let local = settings(port: 1111, toolsOn: false, rules: [("keep", true)])
        let incoming = settings(port: 2222, toolsOn: true, rules: [("in", false)])
        // Rules are appended, master switches or-ed, and this machine's other settings kept.
        let keepThenIn = settings(port: 1111, toolsOn: true, rules: [("keep", true), ("in", false)])
        let inThenKeep = settings(port: 2222, toolsOn: true, rules: [("in", false), ("keep", true)])
        #expect(local.importing(incoming, mode: .append) == keepThenIn)
        #expect(incoming.importing(local, mode: .append) == inThenKeep)
        #expect(local.importing(incoming, mode: .override) == incoming)
    }

    /// A rule set added to `WatcherSettings` but not to the transfer list would silently skip export and import.
    @Test
    func transferListCoversEveryRuleSet() {
        let ruleSetCount = Mirror(reflecting: WatcherSettings()).children
            .filter { String(describing: type(of: $0.value)).hasPrefix("RuleSet<") }.count
        #expect(ruleSetCount == 11)
        #expect(WatcherSettings.ruleSets.count == ruleSetCount)
        #expect(Set(WatcherSettings.ruleSets.map(\.path)).count == ruleSetCount, "no rule set is listed twice")
    }

    @Test
    func blockRulesExportAndImportByMode() {
        var local = WatcherSettings()
        local.port = 1111
        local.blockList = RuleSet(isEnabled: true, rules: [
            BlockRule(name: "keep", matching: MatchingRule(pattern: "a")),
        ])
        var incoming = WatcherSettings()
        incoming.port = 2222
        incoming.blockList = RuleSet(isEnabled: true, rules: [
            BlockRule(name: "on", matching: MatchingRule(pattern: "b")),
            BlockRule(name: "off", isEnabled: false, matching: MatchingRule(pattern: "c")),
        ])

        #expect(incoming.exported(.enabledRules).blockList.rules.map(\.name) == ["on"])
        #expect(incoming.exported(.all).blockList.rules.count == 2)

        let appended = local.importing(incoming, mode: .append)
        #expect(appended.blockList.rules.map(\.name) == ["keep", "on", "off"])
        #expect(appended.port == 1111)
        let replaced = local.importing(incoming, mode: .override)
        #expect(replaced.blockList.rules.count == 2)
        #expect(replaced.port == 2222)
    }

    @Test
    func replacingToolRulesKeepsProtobufPreviewerAndCertificateRules() {
        let local = settings(port: 1111, toolsOn: true, rules: [("keep", true)])
        var incoming = settings(port: 2222, toolsOn: false, rules: [("in", false)])
        incoming.blockList = RuleSet(isEnabled: true, rules: [BlockRule(name: "in", matching: match)])
        var expected = local
        expected.blockList = incoming.blockList
        #expect(local.replacingToolRules(with: incoming) == expected)
    }

    @Test
    func appendImportKeepsThisMachinesSchemasTemplatesAndCustomProfiles() {
        var local = WatcherSettings()
        local.protobufSchemas = ["local.desc"]
        local.breakpointTemplates = [BreakpointTemplate(name: "local", status: 200)]
        local.throttle.customProfiles = [NetworkProfile(name: "local")]
        let incoming = WatcherSettings.everythingChanged
        let merged = local.importing(incoming, mode: .append)
        #expect(merged.protobufSchemas == ["local.desc"])
        #expect(merged.breakpointTemplates.map(\.name) == ["local"])
        #expect(merged.throttle.customProfiles.map(\.name) == ["local"])
    }
}
