import AppKit
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// ⌘F, Find in Body and Find Next, over view trees built here instead of the application's key window.
@MainActor
@Suite(.tags(.unit))
struct FindCommandsTests {
    private final class Recorder {
        var tags: [Int] = []
        var selectors: [Selector] = []
        var filterFocused = 0
    }

    private let recorder = Recorder()

    private func find(window: NSWindow?) -> Find {
        let recorder = recorder
        return Find(
            keyWindow: { window },
            sendAction: { selector, item in
                recorder.selectors.append(selector)
                recorder.tags.append(item.tag)
            }
        )
    }

    private func window(containing views: [NSView]) -> NSWindow {
        let frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        views.forEach(content.addSubview)
        window.contentView = content
        return window
    }

    private func bodyView(findBar: Bool = true, selectable: Bool = true) -> NSTextView {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        text.usesFindBar = findBar
        text.isSelectable = selectable
        return text
    }

    private func show(_ find: Find) {
        find.show(orFocusFilter: { recorder.filterFocused += 1 })
    }

    @Test
    func aFocusedBodyOpensItsFindBar() {
        let body = bodyView()
        let window = window(containing: [body])
        window.makeFirstResponder(body)
        show(find(window: window))
        #expect(recorder.tags == [NSTextFinder.Action.showFindInterface.rawValue])
        #expect(recorder.selectors == [#selector(NSResponder.performTextFinderAction(_:))])
        #expect(recorder.filterFocused == 0)
    }

    @Test
    func aFieldEditorAFindlessTextViewOrNoWindowFocusesTheFilter() {
        let fieldEditor = bodyView()
        fieldEditor.isFieldEditor = true
        let noFindBar = bodyView(findBar: false)
        for responder in [fieldEditor, noFindBar] {
            let window = window(containing: [responder])
            window.makeFirstResponder(responder)
            show(find(window: window))
        }
        show(find(window: nil))
        #expect(recorder.filterFocused == 3)
        #expect(recorder.tags.isEmpty)
    }

    @Test
    func findNextAndPreviousSendTheirActions() {
        let find = find(window: nil)
        find.perform(.nextMatch)
        find.perform(.previousMatch)
        #expect(recorder.tags == [NSTextFinder.Action.nextMatch.rawValue, NSTextFinder.Action.previousMatch.rawValue])
    }

    @Test
    func findInBodyFocusesTheFirstSelectableBodyViewAndOpensItsFindBar() {
        let unselectable = bodyView(selectable: false)
        let noFindBar = bodyView(findBar: false)
        let body = bodyView()
        let window = window(containing: [unselectable, noFindBar, body])
        find(window: window).findInBody()
        #expect(window.firstResponder === body)
        #expect(recorder.tags == [NSTextFinder.Action.showFindInterface.rawValue])
    }

    @Test
    func findInBodyKeepsATextViewThatAlreadyHasFocus() {
        let focused = bodyView()
        let other = bodyView()
        let window = window(containing: [other, focused])
        window.makeFirstResponder(focused)
        find(window: window).findInBody()
        #expect(window.firstResponder === focused)
    }

    @Test
    func findInBodyWithoutAWindowDoesNothing() {
        find(window: nil).findInBody()
        #expect(recorder.tags.isEmpty)
    }

    @Test
    func theFilterFieldIsTheSearchFieldOfTheWindow() {
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        let window = window(containing: [NSView(), field])
        find(window: window).focusFilter(in: window)
        #expect(window.firstResponder === field || window.firstResponder === field.currentEditor())
    }

    @Test
    func aWindowWithoutASearchFieldKeepsItsFocus() {
        let window = window(containing: [bodyView()])
        let before = window.firstResponder
        find(window: window).focusFilter(in: window)
        #expect(window.firstResponder === before)
    }
}
