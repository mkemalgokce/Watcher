import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension EmbeddedDataIndexTests {
    /// How a decoded payload is described, and the limits of the scan.
    @MainActor
    struct Segments {
        private static let payload = Data("a payload long enough to be taken for base64".utf8)

        private func segment(key: String = "k", data: Data) throws -> Base64Segment {
            let body = Data(#"{"\#(key)":"\#(data.base64EncodedString())"}"#.utf8)
            return try #require(EmbeddedDataIndex.scan(body, contentEncoding: nil).first)
        }

        private static let described: [(String, Data, String, String, String)] = [
            ("text", payload, "text/plain", "Text", "doc.text"),
            ("json", Data(#"{"name":"a long enough json document"}"#.utf8), "application/json", "JSON", "curlybraces"),
            ("pdf", Data("%PDF-1.4 all text, nothing binary in it".utf8), "application/pdf", "PDF", "doc.richtext"),
            (
                "binary",
                Data((0 ..< 40).map { UInt8(0x80 + $0 % 100) }),
                "application/octet-stream",
                "Binary",
                "number.square"
            ),
        ]

        @Test(arguments: described)
        func eachKindHasItsMediaTypeNameAndSymbol(
            name: String, data: Data, mime: String, kindName: String, symbol: String
        ) throws {
            let segment = try segment(data: data)
            #expect(segment.mimeType == mime, "\(name)")
            #expect(segment.kindName == kindName, "\(name)")
            #expect(segment.symbol == symbol, "\(name)")
        }

        @Test(arguments: [
            ("invoice", "invoice.json"),
            ("invoice.json", "invoice.json"),
        ])
        func theSuggestedNameKeepsAnExistingExtension(label: String, expected: String) throws {
            let json = Data(#"{"name":"a long enough json document"}"#.utf8)
            #expect(try segment(key: label, data: json).suggestedFileName == expected)
        }

        @Test
        func aDataURILabelWithASlashBecomesAFileNameWithoutOne() {
            let body = Data("data:text/plain;base64,\(Self.payload.base64EncodedString())".utf8)
            let found = EmbeddedDataIndex.scan(body, contentEncoding: nil)
            #expect(found.first?.suggestedFileName == "text-plain.txt")
        }

        private func body(size: Int) -> Data {
            let head = Data(#"{"a":"\#(Self.payload.base64EncodedString())"}"#.utf8)
            return head + Data(repeating: UInt8(ascii: " "), count: size - head.count)
        }

        @Test
        func aBodyAtTheScanLimitIsSearchedAndOneByteMoreIsNot() {
            let limit = EmbeddedDataIndex.scanLimit
            #expect(EmbeddedDataIndex.scan(body(size: limit), contentEncoding: nil).count == 1)
            #expect(EmbeddedDataIndex.scan(body(size: limit + 1), contentEncoding: nil).isEmpty)
        }

        @Test
        func theOldestEntryIsForgottenOnceTheIndexHoldsMoreThanThreeHundredBodies() {
            let index = EmbeddedDataIndex()
            let flows = (0 ... 300).map { number in
                Flow.fixture(
                    sequence: number,
                    request: .fixture(),
                    response: .fixture(body: Data(#"{"a":"\#(Self.payload.base64EncodedString())"}"#.utf8))
                )
            }
            let firstSegments = index.segments(in: flows[0], side: .response)
            for flow in flows.dropFirst() {
                _ = index.segments(in: flow, side: .response)
            }
            let last = index.segments(in: flows[300], side: .response)
            #expect(index.segments(in: flows[300], side: .response).map(\.id) == last.map(\.id), "recent entries stay")
            #expect(index.segments(in: flows[0], side: .response).map(\.id) != firstSegments.map(\.id), "scanned again")
        }
    }
}
