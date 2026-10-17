import AppKit
import PDFKit
import SwiftUI
@testable import WatcherCore
@testable import WatcherUI
import WebKit
import XCTest

@MainActor
final class RichPreviewTests: XCTestCase {
    private func host(_ view: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: 800, height: 600))
        window.layoutIfNeeded()
        return window
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T {
            return match
        }
        for sub in view.subviews {
            if let found = find(type, in: sub) {
                return found
            }
        }
        return nil
    }

    private func wait(_ timeout: TimeInterval, until condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }

    /// The page renders, its own script does not run, and its image is never fetched (a local server sees no request).
    func testHTMLIsRenderedOfflineWithoutScripts() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-pixel-\(UUID()).log")
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", "import http.server,sys\nclass H(http.server.SimpleHTTPRequestHandler):\n  def do_GET(self):\n    open(sys.argv[1],'a').write(self.path+'\\n'); self.send_response(200); self.end_headers()\n  def log_message(self,*a): pass\nhttp.server.HTTPServer(('127.0.0.1',8779),H).serve_forever()", log.path]
        do { try server.run() } catch { throw XCTSkip("python3 unavailable") }
        defer { server.terminate() }
        try await Task.sleep(for: .milliseconds(500))

        let html = """
        <html><head><title>Account</title></head><body><h1>Welcome back</h1>
        <img src="http://127.0.0.1:8779/pixel.png"><script>document.body.innerHTML = 'SCRIPT RAN'</script></body></html>
        """
        let window = host(HTMLPreview(html: html))
        defer { window.close() }
        let web = try XCTUnwrap(find(WKWebView.self, in: window.contentView))
        let loaded = await wait(10) { !web.isLoading && web.title == "Account" }
        XCTAssertTrue(loaded, "the page never finished loading")
        let text = try await web.evaluateJavaScript("document.body.innerText") as? String ?? ""
        XCTAssertTrue(text.contains("Welcome back"), text)
        XCTAssertFalse(text.contains("SCRIPT RAN"), "the page's own JavaScript ran")
        try await Task.sleep(for: .seconds(1))
        let requests = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        XCTAssertTrue(requests.isEmpty, "the preview fetched \(requests)")
    }

    func testPDFOpensWithItsPage() throws {
        let image = NSImage(size: NSSize(width: 595, height: 842), flipped: false) { rect in NSColor.white.setFill(); rect.fill(); return true }
        let document = PDFDocument()
        try document.insert(XCTUnwrap(PDFPage(image: image)), at: 0)
        let window = try host(PDFPreview(data: XCTUnwrap(document.dataRepresentation())))
        defer { window.close() }
        let view = try XCTUnwrap(find(PDFView.self, in: window.contentView))
        XCTAssertEqual(view.document?.pageCount, 1)
        XCTAssertEqual(view.currentPage?.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
    }
}
