import AppKit
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Drives the real body viewer in an off-screen window: the colouring a person sees, not just the tokenizer.
@MainActor
@Suite(.serialized, .tags(.ui))
struct SyntaxTextViewTests {
    private func host(_ text: String, language: BodyLanguage) throws -> (NSWindow, NSTextView) {
        let window = NSWindow.hosting(SyntaxTextView(text, language: language), size: CGSize(width: 900, height: 700))
        return try (window, #require(window.contentView?.firstDescendant(of: NSTextView.self)))
    }

    /// The colour the viewer gave to the character at `index`, or nil when it is still plain.
    private func colour(_ view: NSTextView, at index: Int) -> NSColor? {
        view.layoutManager?
            .temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor
    }

    @Test
    func smallJSONIsColouredImmediately() throws {
        let (window, view) = try host(#"{"name": "Ada", "n": 42}"#, language: .json)
        defer { window.close() }
        #expect(colour(view, at: 2) == SyntaxTextView.Theme.color(.key)) // "name"
        #expect(colour(view, at: 10) == SyntaxTextView.Theme.color(.string)) // "Ada"
        #expect(colour(view, at: 21) == SyntaxTextView.Theme.color(.number)) // 42
        #expect(colour(view, at: 0) == nil) // {
    }

    /// JSON far past the whole-document limit: the window stays usable, the first screen gets coloured once parsing ends, and so does a screen
    /// scrolled to the middle of the document.
    @Test
    func largeJSONIsColouredOnScreenAndAfterScrolling() async throws {
        let item = #"{"id":12345,"name":"Ada Lovelace","tags":["a","b",null,true],"score":-1.5e3},"#
        // ~400 KB is enough to take the visible-range path; 30 MB held the main actor long enough to fail other suites
        let text = "[" + String(repeating: item, count: 5000) + #"{"end":1}]"#
        let pretty = JSONFormatter.pretty(text)
        let (window, view) = try host(pretty, language: .json)
        defer { window.close() }

        let firstKey = (pretty as NSString).range(of: "\"id\"").location
        let firstScreenColoured = await eventually(timeout: 30) { colour(view, at: firstKey + 1) != nil }
        #expect(firstScreenColoured, "first screen never got coloured")
        #expect(colour(view, at: firstKey + 1) == SyntaxTextView.Theme.color(.key))

        // Jump to the middle and check that this part is coloured as well (it was not when the document opened).
        let middleRange = NSRange(location: (pretty as NSString).length / 2, length: 10000)
        let middle = (pretty as NSString).range(of: "\"name\"", range: middleRange).location
        #expect(colour(view, at: middle + 1) == nil, "only the visible part should be coloured up front")
        view.scrollRangeToVisible(NSRange(location: middle, length: 1))
        let middleColoured = await eventually(timeout: 5) { colour(view, at: middle + 1) != nil }
        #expect(middleColoured, "scrolled-to part never got coloured")
        #expect(colour(view, at: middle + 1) == SyntaxTextView.Theme.color(.key))
    }
}
