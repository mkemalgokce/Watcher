import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Base64 payloads inside a body: found, described for saving, and scanned once per body.
@MainActor
struct EmbeddedDataIndexTests {
    @Test
    func embeddedBase64IsFoundAndDescribed() {
        // A 1×1 PNG and a small PDF header inside JSON, as an API would return them.
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let pdf = Data("%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF".utf8)
            .base64EncodedString()
        let body = Data(#"{"avatar":"\#(png)","invoice":"\#(pdf)","name":"Ada"}"#.utf8)
        let segments = EmbeddedDataIndex.scan(body, contentEncoding: nil)
        #expect(segments.count == 2)
        let image = segments.first {
            if case .image = $0.kind {
                true
            } else {
                false
            }
        }
        #expect(image?.label == "avatar")
        #expect(image?.mimeType == "image/png")
        #expect(image?.suggestedFileName == "avatar.png")
        let document = segments.first { $0.isPDF }
        #expect(document?.kindName == "PDF")
        #expect(document?.suggestedFileName == "invoice.pdf")

        #expect(EmbeddedDataIndex.scan(Data(), contentEncoding: nil).isEmpty)
        #expect(
            EmbeddedDataIndex.scan(Data(repeating: 0xFF, count: 64), contentEncoding: nil).isEmpty,
            "binary bodies are not searched"
        )
    }

    @Test
    func embeddedResultsAreCachedPerBody() {
        let index = EmbeddedDataIndex()
        let flow = Flow.fixture(
            response: .fixture(body: Data(#"{"a":"aGVsbG8gd29ybGQsIHRoaXMgaXMgYSB0ZXN0IHN0cmluZw=="}"#.utf8))
        )
        let first = index.segments(in: flow, side: .response)
        let second = index.segments(in: flow, side: .response)
        #expect(first.map(\.id) == second.map(\.id), "the second call is answered from the cache")
        #expect(index.segments(in: flow, side: .request).isEmpty)
    }
}
