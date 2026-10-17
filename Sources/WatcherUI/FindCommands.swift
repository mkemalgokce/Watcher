import AppKit

/// ⌘F does what people expect in a two-pane tool: inside a body it opens that text's Find bar, anywhere else it jumps to the request filter.
@MainActor
enum Find {
    static func show(orFocusFilter focusFilter: () -> Void) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, !text.isFieldEditor, text.usesFindBar {
            return perform(.showFindInterface)
        }
        focusFilter()
    }

    static func perform(_ action: NSTextFinder.Action) {
        let item = NSMenuItem(); item.tag = action.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }

    /// The first body viewer in the window, so "Find in Body" works without clicking into it first.
    static func findInBody() {
        guard let window = NSApp.keyWindow else { return }
        if !(window.firstResponder is NSTextView), let text = firstBodyView(in: window.contentView) {
            window.makeFirstResponder(text)
        }
        perform(.showFindInterface)
    }

    static func focusFilter(in window: NSWindow) {
        guard let field = searchField(in: window.contentView?.superview ?? window.contentView) else { return }
        window.makeFirstResponder(field)
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField {
            return field
        }
        for sub in view.subviews {
            if let found = searchField(in: sub) {
                return found
            }
        }
        return nil
    }

    private static func firstBodyView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let text = view as? NSTextView, text.usesFindBar, !text.isFieldEditor, text.isSelectable {
            return text
        }
        for sub in view.subviews {
            if let found = firstBodyView(in: sub) {
                return found
            }
        }
        return nil
    }
}
