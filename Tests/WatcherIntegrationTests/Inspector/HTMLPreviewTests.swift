import AppKit
import Foundation
import Testing
import WatcherTestSupport
@testable import WatcherUI
import WebKit

/// An HTML body shown in the inspector's preview, which must stay offline and inert.
@MainActor
@Suite(
    .timeLimit(.minutes(1)),
    .serialized,
    .tags(.integration, .ui, .externalTool),
    .enabled(if: ExternalTool.python3.isAvailable, "python3 serves the page's image")
)
struct HTMLPreviewTests {
    /// Logs the path of every request it gets to the file named by its first argument.
    private static let loggingServer = """
    import http.server,sys
    class H(http.server.SimpleHTTPRequestHandler):
      def do_GET(self):
        open(sys.argv[1],'a').write(self.path+'\\n'); self.send_response(200); self.end_headers()
      def log_message(self,*a): pass
    s = http.server.HTTPServer(('127.0.0.1',0),H)
    print(s.server_address[1], flush=True)
    s.serve_forever()
    """

    /// The page renders, its own script does not run, and its image and stylesheet are never fetched (a local server sees no request).
    @Test
    func htmlIsRenderedOfflineWithoutScripts() async throws {
        let directory = try TemporaryDirectory(prefix: "watcher-pixel")
        let server = try PythonServer(script: Self.loggingServer, arguments: [directory.appending("requests.log").path])

        let html = """
        <html><head><title>Account</title></head><body><h1>Welcome back</h1>
        <link rel="stylesheet" href="http://127.0.0.1:\(server.port)/style.css">
        <img src="http://127.0.0.1:\(server.port)/pixel.png"><script>document.body.innerHTML = 'SCRIPT RAN'</script>
        </body></html>
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

        // The server answers one request at a time, so a fetch the page made is logged before this probe.
        let probe = HTTPClientRequestHelper.url("http://127.0.0.1:\(server.port)/probe")
        _ = try await HTTPClientRequestHelper.fetch(probe)
        #expect(server.isRunning, "the server must be up for its silence to mean anything")
        let requests = try String(contentsOf: directory.appending("requests.log"), encoding: .utf8)
        #expect(requests == "/probe\n", "the preview fetched \(requests)")
    }
}
