import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct RulesCommandTests {
    @Test(arguments: [(["out.json"], "all"), (["out.json", "--mode", "enabledRules"], "enabledRules")])
    func exportModeDefaultsToAll(arguments: [String], mode: String) throws {
        let export = try Rules.Export.parse(arguments)
        #expect(export.path == "out.json")
        #expect(export.mode == mode)
    }

    @Test(arguments: [(["in.json"], "override"), (["in.json", "--mode", "append"], "append")])
    func importModeDefaultsToOverride(arguments: [String], mode: String) throws {
        let rules = try Rules.Import.parse(arguments)
        #expect(rules.path == "in.json")
        #expect(rules.mode == mode)
    }

    @Test
    func subcommandsAreExportImportAndImportCharles() throws {
        #expect(try Rules.parseAsRoot(["export", "a.json"]) is Rules.Export)
        #expect(try Rules.parseAsRoot(["import", "a.json"]) is Rules.Import)
        #expect(try Rules.parseAsRoot(["import-charles", "a.xml"]) is ImportCharles)
    }

    @Test(arguments: [["export"], ["import"], ["import-charles"]])
    func everySubcommandNeedsAPath(arguments: [String]) {
        #expect(throws: (any Error).self) { try Rules.parseAsRoot(arguments) }
    }
}
