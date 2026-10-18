import Testing
@testable import WatcherUI
import WebKit

@MainActor
@Suite(.tags(.unit))
struct OfflineHTMLTests {
    private func shown(blocking succeeds: Bool) -> [String] {
        var pages: [String] = []
        OfflineHTML.load(
            "<img src=\"http://x.test/a.png\">",
            blockNetwork: { done in done(succeeds) },
            show: { pages.append($0) }
        )
        return pages
    }

    @Test
    func thePageIsShownOnceEveryNetworkLoadIsBlocked() {
        #expect(shown(blocking: true) == ["<img src=\"http://x.test/a.png\">"])
    }

    @Test
    func whenBlockingFailsOnlyAPageWithoutSubresourcesIsShown() {
        let pages = shown(blocking: false)
        #expect(pages == [OfflineHTML.unavailable])
        #expect(!OfflineHTML.unavailable.contains("src="))
        #expect(!OfflineHTML.unavailable.contains("href="))
    }

    @Test
    func nothingIsShownUntilBlockingHasFinished() {
        var pages: [String] = []
        var finish: ((Bool) -> Void)?
        OfflineHTML.load("<p>x</p>", blockNetwork: { finish = $0 }, show: { pages.append($0) })
        #expect(pages.isEmpty)
        finish?(true)
        #expect(pages == ["<p>x</p>"])
    }

    @Test
    func aRuleListThatCannotBeCompiledReportsNotBlocked() {
        let controller = WKUserContentController()
        var reported: [Bool] = []
        OfflineHTML.blockNetwork(in: controller, compile: { $0(nil) }, done: { reported.append($0) })
        #expect(reported == [false])
    }
}
