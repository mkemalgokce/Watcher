import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.unit))
struct StatusBarTextTests {
    @Test(arguments: [
        (["*"], [String](), "HTTPS decrypted", true),
        (["*"], ["a.test"], "HTTPS: all but 1 host", false),
        (["*"], ["a.test", "b.test"], "HTTPS: all but 2 hosts", false),
        (["a.test"], [], "HTTPS: 1 host", false),
        (["a.test", "b.test", "c.test"], [], "HTTPS: 3 hosts", false),
        (["a.test"], ["b.test"], "HTTPS: 1 host", false),
        ([], [], "HTTPS: not decrypted", false),
        ([], ["a.test"], "HTTPS: not decrypted", false),
    ])
    func theHTTPSItemSaysWhatIsDecrypted(include: [String], exclude: [String], text: String, all: Bool) {
        let https = StatusBarText.https(SSLProxyingSettings(include: include, exclude: exclude))
        #expect(https == StatusBarText.HTTPS(text: text, decryptsAll: all))
    }

    @Test
    func oneToolIsNamedAndSeveralAreCounted() {
        #expect(StatusBarText.tools(["Block List"]) == "Block List")
        #expect(StatusBarText.tools(["Block List", "Map Local"]) == "2 tools on")
    }

    @Test(arguments: [
        (0, "Map Local, Block List, Scripting and the other tools (⌘T)"),
        (1, "1 tool rule is changing traffic (⌘T)"),
        (2, "2 tool rules are changing traffic (⌘T)"),
    ])
    func theToolbarBadgeHelpAgreesWithTheCount(count: Int, help: String) {
        #expect(StatusBarText.toolRulesHelp(count) == help)
    }
}
