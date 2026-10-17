#if DEBUG
    import AppKit
    import PDFKit
    import WatcherCore

    /// A model showing one captured exchange with the given response body, for checking how a content type is previewed.
    @MainActor func singleResponse(_ type: String, _ body: Data, path: String) -> AppModel {
        UserDefaults.standard.set("Preview", forKey: "body.mode")
        let model = AppModel(listening: false)
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "docs.example.com", port: 443, path: path, clientApp: "Safari"))
        flow.response = ResponseRecord(status: 200, headers: [Header("Content-Type", type)], body: body)
        flow.state = .completed; flow.duration = 0.2
        model.engine.store.load([flow]); model.syncFromStore(); model.selection = model.flows.first?.id
        return model
    }

    /// A one-page PDF, so the preview shows a real document.
    @MainActor func samplePDF() -> Data {
        let image = NSImage(size: NSSize(width: 595, height: 842), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            NSColor.systemBlue.setFill(); NSRect(x: 60, y: 700, width: 475, height: 80).fill()
            ("Invoice #2026-17" as NSString).draw(at: NSPoint(x: 60, y: 640), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.black])
            return true
        }
        let document = PDFDocument()
        if let page = PDFPage(image: image) {
            document.insert(page, at: 0)
        }
        return document.dataRepresentation() ?? Data()
    }
#endif
