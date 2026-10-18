import AppKit

enum LiveSearchFocus {
    /// Before macOS 15 the toolbar search field cannot be focused from SwiftUI, so the key window's is found in AppKit.
    static let focusFilterField: @MainActor () -> Void = {
        if #unavailable(macOS 15.0), let window = NSApp.keyWindow {
            Find.live.focusFilter(in: window)
        }
    }
}
