import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// What a body viewer shows for a body and the chosen options: the modes offered, the mode in effect, the text and the
/// line above it.
@Suite(.tags(.unit))
struct BodyRenderingTests {
    private let json = Data(#"{"b":1,"a":{"name":"Ada"}}"#.utf8)

    private func appears(_ first: String, before second: String, in text: String) -> Bool {
        guard let one = text.range(of: first), let other = text.range(of: second) else { return false }
        return one.lowerBound < other.lowerBound
    }

    private func prepare(_ body: Data, mode: BodyMode, sortKeys: Bool, path: String = "") -> BodyRendering.Prepared {
        BodyRendering.prepare(body, contentType: "application/json", mode: mode, sortKeys: sortKeys, path: path)
    }

    @Test
    func prettyJSONIsIndentedAndKeysSortOnRequest() {
        let plain = prepare(json, mode: .pretty, sortKeys: false)
        let sorted = prepare(json, mode: .pretty, sortKeys: true)
        #expect(plain.language == .json)
        #expect(plain.text.contains("\n"))
        #expect(appears(#""b""#, before: #""a""#, in: plain.text))
        #expect(appears(#""a""#, before: #""b""#, in: sorted.text))
    }

    @Test
    func rawShowsTheBytesAsTheyCameAndHexDumpsThem() {
        let raw = prepare(json, mode: .raw, sortKeys: true)
        #expect(raw.text == String(bytes: json, encoding: .utf8))
        #expect(raw.note == "raw")
        let hex = prepare(json, mode: .hex, sortKeys: false)
        #expect(hex.language == .binary)
        #expect(hex.text == BodyFormatter.hexDump(json))
    }

    @Test
    func rawFallsBackToHexForBytesThatAreNotText() {
        let bytes = Data([0xFF, 0xFE, 0x00, 0x81])
        let raw = BodyRendering.prepare(bytes, contentType: nil, mode: .raw, sortKeys: false)
        #expect(raw.text == BodyFormatter.hexDump(bytes))
    }

    @Test
    func aJSONPathNarrowsTheText() {
        let filtered = prepare(json, mode: .pretty, sortKeys: false, path: "a.name")
        #expect(filtered.text.trimmingCharacters(in: .whitespacesAndNewlines) == #""Ada""#)
        #expect(!filtered.pathFailed)
    }

    @Test
    func aFilterThatCannotRunKeepsTheWholeBodyAndSaysSo() {
        let broken = Data(#"{"a": "#.utf8)
        let full = prepare(broken, mode: .pretty, sortKeys: false)
        let missed = prepare(broken, mode: .pretty, sortKeys: false, path: "a")
        #expect(missed.pathFailed)
        #expect(missed.text == full.text)
    }

    @Test
    func aFilterOnTextThatIsNotJSONIsIgnored() {
        let body = Data("a.name".utf8)
        let text = BodyRendering.prepare(body, contentType: "text/plain", mode: .pretty, sortKeys: false, path: "a")
        #expect(!text.pathFailed)
        #expect(text.text == "a.name")
    }

    @Test
    func longTextIsCutOnAWholeLineAndRemembersItsFullSize() {
        let body = Data((1 ... 100).map { "line \($0)" }.joined(separator: "\n").utf8)
        let cut = BodyRendering.prepare(body, contentType: "text/plain", mode: .pretty, sortKeys: false, limit: 50)
        #expect(cut.cutFrom == body.count)
        #expect(cut.text.utf8.count <= 50)
        #expect(cut.text.hasSuffix("line 7"))
        let whole = BodyRendering.prepare(body, contentType: "text/plain", mode: .pretty, sortKeys: false, limit: nil)
        #expect(whole.cutFrom == nil)
    }

    @Test
    func gzipIsUndoneBeforeTheRichKindIsChosen() {
        let html = Data("<html><body>hi</body></html>".utf8)
        let key = BodyRendering.UnpackKey(flow: UUID(), side: .response, size: 0)
        let unpacked = BodyRendering.unpack(key, html.gzipped, contentType: "text/html", encoding: "gzip")
        #expect(unpacked.data == html)
        #expect(unpacked.richKind == .html)
        #expect(BodyRendering.unpack(key, Data(), contentType: "text/html", encoding: nil).richKind == nil)
    }

    @Test(arguments: [
        (BodyMode.preview, RichKind?.some(.image), BodyMode.preview),
        (.preview, nil, .pretty),
        (.raw, .image, .raw),
        (.hex, nil, .hex),
    ])
    func previewIsOnlyKeptForBodiesThatCanBeRendered(chosen: BodyMode, richKind: RichKind?, expected: BodyMode) {
        #expect(BodyRendering.effectiveMode(chosen: chosen, richKind: richKind) == expected)
    }

    @Test
    func previewIsOfferedOnlyWhenThereIsSomethingToRender() {
        #expect(BodyRendering.modes(richKind: .pdf) == BodyMode.allCases)
        #expect(BodyRendering.modes(richKind: nil) == [.pretty, .raw, .hex])
    }

    @Test(arguments: [
        (RichKind.image, "Image"), (.html, "HTML, rendered offline"), (.pdf, "PDF"), (.media, "Audio / video"),
        (.eventStream, "Server-Sent Events"), (.form, "Form fields"),
    ])
    func aRenderedBodyIsSummedUpByItsKind(kind: RichKind, expected: String) {
        #expect(BodyRendering.summary(mode: .preview, richKind: kind, prepared: nil) == expected)
    }

    @Test
    func textIsSummedUpByItsLanguageAndNote() {
        let raw = prepare(json, mode: .raw, sortKeys: false)
        #expect(BodyRendering.summary(mode: .raw, richKind: .image, prepared: raw) == "JSON · raw")
        #expect(BodyRendering.summary(mode: .pretty, richKind: nil, prepared: nil) == "…")
    }

    @Test
    func graphQLDetectionCanBeTurnedOffToKeepTheJSON() {
        let envelope = Data(#"{"query":"{ viewer { id } }"}"#.utf8)
        let detected = BodyRendering.prepare(envelope, contentType: "application/json", mode: .pretty, sortKeys: false)
        let plain = BodyRendering.prepare(
            envelope, contentType: "application/json", mode: .pretty, sortKeys: false, detectsGraphQL: false
        )
        #expect(detected.language == .graphql)
        #expect(plain.language == .json)
    }

    @Test(arguments: [
        ("application/json", #"{"a":1}"#, true), ("application/vnd.api+json; charset=utf-8", "[1]", true),
        // The header decides; the viewer falls back to text if the body will not parse.
        ("application/json", "not even json", true),
        (nil, #"{"a":1}"#, true), ("text/plain", "[1, 2]", true),
        ("text/plain", "[draft]", false), ("text/plain", "hello", false), (nil, "{broken", false),
        ("text/html", #"{"a":1}"#, false),
    ])
    func jsonBodiesCanBeShownAsATree(contentType: String?, body: String, isJSON: Bool) {
        let kind = RichKind.of(contentType: contentType, data: Data(body.utf8))
        #expect((kind == .json) == isJSON)
    }

    @Test
    func aFormIsStillAFormEvenWhenAFieldHoldsJSON() {
        let kind = RichKind.of(contentType: "application/x-www-form-urlencoded", data: Data(#"a=%7B%7D"#.utf8))
        #expect(kind == .form)
    }

    @Test
    func theRenderedTabIsCalledTreeForJSONAndPreviewForTheRest() {
        #expect(BodyRendering.title(of: .preview, richKind: .json) == "Tree")
        #expect(BodyRendering.title(of: .preview, richKind: .image) == "Preview")
        #expect(BodyRendering.title(of: .raw, richKind: .json) == "Raw")
        #expect(BodyRendering.symbol(of: .preview, richKind: .json) == "list.bullet.indent")
        #expect(BodyRendering.symbol(of: .preview, richKind: .pdf) == "eye")
    }

    @Test
    func jsonKeepsThePreviewTab() {
        #expect(BodyRendering.modes(richKind: .json) == BodyMode.allCases)
        #expect(BodyRendering.effectiveMode(chosen: .preview, richKind: .json) == .preview)
    }

    @Test
    func theTreeNeedsNoSummaryBecauseItsTabAlreadySaysTree() {
        #expect(BodyRendering.summary(mode: .preview, richKind: .json, prepared: nil).isEmpty)
    }

    @Test(arguments: [
        ("application/yaml", true), ("text/yaml; charset=utf-8", true), ("application/x-yaml", true),
        ("application/vnd.kubernetes+yaml", true), ("text/x-yaml", true),
        ("text/plain", false), (nil, false), ("application/json", false),
    ])
    func yamlIsRecognisedByItsHeaderOnly(contentType: String?, isYAML: Bool) {
        let kind = RichKind.of(contentType: contentType, data: Data("a: 1\nb: [1, 2]\n".utf8))
        #expect((kind == .yaml) == isYAML)
    }

    @Test
    func yamlGetsTheTreeTabToo() {
        #expect(BodyRendering.title(of: .preview, richKind: .yaml) == "Tree")
        #expect(BodyRendering.symbol(of: .preview, richKind: .yaml) == "list.bullet.indent")
        #expect(BodyRendering.summary(mode: .preview, richKind: .yaml, prepared: nil) == "YAML")
        #expect(BodyRendering.modes(richKind: .yaml) == BodyMode.allCases)
    }
}
