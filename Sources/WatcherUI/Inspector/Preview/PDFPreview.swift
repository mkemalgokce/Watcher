import PDFKit
import SwiftUI

struct PDFPreview: NSViewRepresentable {
    let data: Data
    func makeNSView(context _: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_: PDFView, context _: Context) {}
}
