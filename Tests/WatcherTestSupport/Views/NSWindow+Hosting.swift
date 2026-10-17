import AppKit
import SwiftUI

public extension NSWindow {
    /// An off-screen window that has laid out `view` at `size`; the caller closes it.
    @MainActor
    static func hosting(_ view: some View, size: CGSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false // ARC owns it; AppKit releasing it again on close() would crash
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.layoutIfNeeded()
        return window
    }
}
