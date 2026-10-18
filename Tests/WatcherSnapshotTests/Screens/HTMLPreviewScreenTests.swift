import AppKit
import Testing
import WatcherTestSupport
@testable import WatcherUI
import WebKit

/// An HTML response as the inspector's preview renders it: laid out like a browser would, with no script run.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct HTMLPreviewScreenTests {
    private static let page = """
    <html><head><title>Account</title>
    <style>body { font: 15px -apple-system; margin: 24px; }
    th, td { text-align: left; padding: 4px 12px 4px 0; }</style>
    </head><body>
    <h1>Welcome back, Ada</h1>
    <p>Your plan renews on <b>1 December</b>.</p>
    <table><tr><th>Invoice</th><th>Total</th></tr><tr><td>#1042</td><td>€12.00</td></tr></table>
    <script>document.body.innerHTML = '<h1>SCRIPT RAN</h1>'</script>
    </body></html>
    """

    @Test
    func aPageIsRenderedWithoutItsScript() async throws {
        let window = NSWindow.hosting(HTMLPreview(html: Self.page), size: CGSize(width: 640, height: 320))
        window.appearance = NSAppearance(named: .aqua)
        defer { window.close() }
        let web = try #require(window.contentView?.firstDescendant(of: WKWebView.self))
        let loaded = await eventually(timeout: 10, poll: .milliseconds(100)) {
            !web.isLoading && web.title == "Account"
        }
        try #require(loaded, "the page never finished loading")
        try await ImageSnapshot.verify(page: web, named: "page")
    }
}
