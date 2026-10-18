import AppKit
import SwiftUI

/// A screen shown in a real window, driven through accessibility the way a user or UI automation drives it.
@MainActor
public final class TestWindow {
    private let window: NSWindow

    /// The same kind of window the app opens, so the toolbar gets the same room and layout (the centre item included).
    public init(showing view: some View, width: CGFloat = 1000, height: CGFloat = 640) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: width, height: height))
        window.orderFront(nil)
    }

    public func close() {
        window.close()
    }

    /// Every element whose accessibility title, description or value is `label`. Interaction suites run alone and one
    /// at a time (`make test-interaction`), so every window of the process is this one.
    public func elements(_ label: String) -> [AXUIElement] {
        AccessibilityAPI.find(label)
    }

    /// Whether an element labelled `label` shows up within the default wait.
    public func shows(_ label: String) async -> Bool {
        await eventually { !elements(label).isEmpty }
    }

    /// The first non-nil `find()` within the default wait, or nil when the element never shows up.
    public func appearing(_ find: () -> AXUIElement?) async -> AXUIElement? {
        var element: AXUIElement?
        _ = await eventually { element = find(); return element != nil }
        return element
    }

    /// Presses the control labelled `label`, waiting for it to appear; a label's text matches too, but only something
    /// pressable is pressed.
    public func press(_ label: String) async throws {
        let control = await appearing { elements(label).first(where: AccessibilityAPI.canPress) }
        guard let control else { throw TestSupportError("no control labelled “\(label)”") }
        let result = AccessibilityAPI.press(control)
        await settle()
        guard result == .success else { throw TestSupportError("“\(label)” did not respond to a press (\(result))") }
    }

    /// Types into the first editable element with `role` whose value starts with `prefix` (empty matches an empty field).
    public func type(_ text: String, intoFieldWithValue prefix: String = "", role: String) async -> Bool {
        let field = await appearing { AccessibilityAPI.firstElement(withRole: role, valuePrefix: prefix) }
        guard let field else { return false }
        let typed = AccessibilityAPI.setValue(text, of: field)
        await settle()
        return typed
    }
}

/// Shows `view` in a `TestWindow` for the length of `body` and closes it afterwards, also when `body` throws.
@MainActor
public func withWindow(
    showing view: some View,
    width: CGFloat = 1000,
    height: CGFloat = 640,
    _ body: (TestWindow) async throws -> Void
) async rethrows {
    let window = TestWindow(showing: view, width: width, height: height)
    defer { window.close() }
    await settle()
    try await body(window)
}
