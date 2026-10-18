import AppKit
import PDFKit
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// A PDF body shown in the inspector's preview.
@MainActor
@Suite(.serialized, .tags(.ui))
struct PDFPreviewTests {
    @Test
    func pdfOpensWithItsPage() throws {
        let image = NSImage(size: NSSize(width: 595, height: 842), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
        let document = PDFDocument()
        try document.insert(#require(PDFPage(image: image)), at: 0)
        let preview = try PDFPreview(data: #require(document.dataRepresentation()))
        let window = NSWindow.hosting(preview, size: CGSize(width: 800, height: 600))
        defer { window.close() }
        let view = try #require(window.contentView?.firstDescendant(of: PDFView.self))
        #expect(view.document?.pageCount == 1)
        #expect(view.currentPage?.bounds(for: .mediaBox).size == CGSize(width: 595, height: 842))
    }
}
