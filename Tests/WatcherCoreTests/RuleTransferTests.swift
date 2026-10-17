@testable import WatcherCore
import XCTest

/// Export and append-import must cover every tool's rules, not only the eight the transfer code first listed.
final class RuleTransferTests: XCTestCase {
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

    func testEnabledRulesExportDropsDisabledProtobufPreviewerAndCertificateRules() {
        let all = settings(port: 1111, toolsOn: true, rules: [("on", true), ("off", false)])
        XCTAssertEqual(all.exported(.enabledRules), settings(port: 1111, toolsOn: true, rules: [("on", true)]))
        XCTAssertEqual(all.exported(.all), all)
    }

    func testEnabledRulesExportKeepsSwitchedOffTools() {
        let off = settings(port: 1111, toolsOn: false, rules: [("on", true), ("off", false)])
        XCTAssertEqual(off.exported(.enabledRules), settings(port: 1111, toolsOn: false, rules: [("on", true)]))
    }

    func testAppendImportAddsProtobufPreviewerAndCertificateRules() {
        let local = settings(port: 1111, toolsOn: false, rules: [("keep", true)])
        let incoming = settings(port: 2222, toolsOn: true, rules: [("in", false)])
        // Rules are appended, master switches or-ed, and this machine's other settings kept.
        let keepThenIn = settings(port: 1111, toolsOn: true, rules: [("keep", true), ("in", false)])
        let inThenKeep = settings(port: 2222, toolsOn: true, rules: [("in", false), ("keep", true)])
        XCTAssertEqual(local.importing(incoming, mode: .append), keepThenIn)
        XCTAssertEqual(incoming.importing(local, mode: .append), inThenKeep)
        XCTAssertEqual(local.importing(incoming, mode: .override), incoming)
    }

    /// A rule set added to `WatcherSettings` but not to the transfer list would silently skip export and import.
    func testTransferListCoversEveryRuleSet() {
        let ruleSetCount = Mirror(reflecting: WatcherSettings()).children
            .filter { String(describing: type(of: $0.value)).hasPrefix("RuleSet<") }.count
        XCTAssertEqual(ruleSetCount, 11)
        XCTAssertEqual(WatcherSettings.ruleSets.count, ruleSetCount)
        XCTAssertEqual(Set(WatcherSettings.ruleSets.map(\.path)).count, ruleSetCount, "no rule set is listed twice")
    }
}
