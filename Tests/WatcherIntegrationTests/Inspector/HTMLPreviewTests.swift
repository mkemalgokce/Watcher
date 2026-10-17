import AppKit
import Foundation
import Testing
import WatcherTestSupport
@testable import WatcherUI
import WebKit

/// An HTML body shown in the inspector's preview, which must stay offline and inert.
@MainActor
@Suite(
    .serialized,
    .tags(.integration, .ui, .externalTool),
    .enabled(if: ExternalTool.python3.isAvailable, "python3 serves the page's image")
)
struct HTMLPreviewTests {
    private static let pixelServer = """
    import http.server,sys
    class H(http.server.SimpleHTTPRequestHandler):
      def do_GET(self):
        open(sys.argv[1],'a').write(self.path+'\\n'); self.send_response(200); self.end_headers()
      def log_message(self,*a): pass
    http.server.HTTPServer(('127.0.0.1',8779),H).serve_forever()
    """

    /// The page renders, its own script does not run, and its image is never fetched (a local server sees no request).
    @Test
    func htmlIsRenderedOfflineWithoutScripts() async throws {
        let directory = try TemporaryDirectory(prefix: "watcher-pixel")
        let log = directory.appending("requests.log")
        let server = Process()
        server.executableURL = try ExternalTool.python3.require()
        server.arguments = ["-c", Self.pixelServer, log.path]
        try server.run()
        defer { server.terminate() }
        try await Task.sleep(for: .milliseconds(500))

        let html = """
        <html><head><title>Account</title></head><body><h1>Welcome back</h1>
        <img src="http://127.0.0.1:8779/pixel.png"><script>document.body.innerHTML = 'SCRIPT RAN'</script></body></html>
        """
        let window = NSWindow.hosting(HTMLPreview(html: html), size: CGSize(width: 800, height: 600))
        defer { window.close() }
        let web = try #require(window.contentView?.firstDescendant(of: WKWebView.self))
        let loaded = await eventually(timeout: 10, poll: .milliseconds(100)) {
            !web.isLoading && web.title == "Account"
        }
        #expect(loaded, "the page never finished loading")
        let text = try await web.evaluateJavaScript("document.body.innerText") as? String ?? ""
        #expect(text.contains("Welcome back"), "\(text)")
        #expect(!text.contains("SCRIPT RAN"), "the page's own JavaScript ran")
        try await Task.sleep(for: .seconds(1))
        let requests = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(requests.isEmpty, "the preview fetched \(requests)")
    }
}
