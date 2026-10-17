import AppKit
import SwiftUI
@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// Drives the real body viewer in an off-screen window: the colouring a person sees, not just the tokenizer.
@MainActor
final class SyntaxTextViewTests: XCTestCase {
    private func host(_ text: String, language: BodyLanguage) -> (NSWindow, NSTextView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false // ARC owns it; AppKit releasing it again on close() would crash
        window.contentView = NSHostingView(rootView: SyntaxTextView(text, language: language).frame(width: 900, height: 700))
        window.layoutIfNeeded()
        return (window, textView(in: window.contentView)!)
    }

    private func textView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let text = view as? NSTextView {
            return text
        }
        for sub in view.subviews {
            if let found = textView(in: sub) {
                return found
            }
        }
        return nil
    }

    /// The colour the viewer gave to the character at `index`, or nil when it is still plain.
    private func colour(_ view: NSTextView, at index: Int) -> NSColor? {
        view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor
    }

    private func wait(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func testSmallJSONIsColouredImmediately() {
        let (window, view) = host(#"{"name": "Ada", "n": 42}"#, language: .json)
        defer { window.close() }
        XCTAssertEqual(colour(view, at: 2), SyntaxTextView.Theme.color(.key)) // "name"
        XCTAssertEqual(colour(view, at: 10), SyntaxTextView.Theme.color(.string)) // "Ada"
        XCTAssertEqual(colour(view, at: 21), SyntaxTextView.Theme.color(.number)) // 42
        XCTAssertNil(colour(view, at: 0)) // {
    }

    /// 30+ MB of JSON: the window stays usable, the first screen gets coloured once parsing ends, and so does a screen
    /// scrolled to the middle of the document.
    func testLargeJSONIsColouredOnScreenAndAfterScrolling() {
        let item = #"{"id":12345,"name":"Ada Lovelace","tags":["a","b",null,true],"score":-1.5e3},"#
        let text = "[" + String(repeating: item, count: 400_000) + #"{"end":1}]"# // ~31 MB
        let pretty = JSONFormatter.pretty(text)
        let (window, view) = host(pretty, language: .json)
        defer { window.close() }

        let firstKey = (pretty as NSString).range(of: "\"id\"").location
        XCTAssertTrue(wait(timeout: 30) { colour(view, at: firstKey + 1) != nil }, "first screen never got coloured")
        XCTAssertEqual(colour(view, at: firstKey + 1), SyntaxTextView.Theme.color(.key))

        // Jump to the middle and check that this part is coloured as well (it was not when the document opened).
        let middle = (pretty as NSString).range(of: "\"name\"", range: NSRange(location: (pretty as NSString).length / 2, length: 10000)).location
        XCTAssertNil(colour(view, at: middle + 1), "only the visible part should be coloured up front")
        view.scrollRangeToVisible(NSRange(location: middle, length: 1))
        XCTAssertTrue(wait(timeout: 5) { colour(view, at: middle + 1) != nil }, "scrolled-to part never got coloured")
        XCTAssertEqual(colour(view, at: middle + 1), SyntaxTextView.Theme.color(.key))
    }
}
