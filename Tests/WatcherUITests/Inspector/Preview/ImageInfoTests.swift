import Foundation
import Testing
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.unit))
struct ImageInfoTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test(arguments: [("image/png", "PNG"), ("image/svg+xml", "SVG+XML"), ("image/jpeg", "JPEG"), ("", "")])
    func theTypeLabelIsTheUppercasedSubtype(mime: String, label: String) {
        #expect(ImageInfo.typeLabel(mime: mime) == label)
    }

    @Test
    func theDeclaredTypeWinsOverTheBytes() {
        #expect(ImageInfo.mime(declared: "image/webp", data: Self.png) == "image/webp")
        #expect(ImageInfo.mime(declared: nil, data: Self.png) == "image/png")
        #expect(ImageInfo.mime(declared: nil, data: Data("text".utf8)) == nil)
    }

    @Test
    func theSummaryNamesSizeTypeAndBytes() {
        let declared = ImageInfo.summary(width: 640, height: 480, declaredMime: "image/png", data: Self.png)
        #expect(declared.hasPrefix("640 × 480 · PNG · "))
        #expect(ImageInfo.summary(width: 1, height: 2, declaredMime: nil, data: Self.png).hasPrefix("1 × 2 · PNG · "))
        #expect(ImageInfo.summary(width: 1, height: 2, declaredMime: nil, data: Data()).hasPrefix("1 × 2 · IMAGE · "))
    }
}
