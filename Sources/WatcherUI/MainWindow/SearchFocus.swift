import SwiftUI

/// Lets the menu command move focus into the toolbar search field. `searchFocused` needs macOS 15; earlier systems use AppKit (see `Find`).
struct SearchFocus: ViewModifier {
    let request: Int
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused($focused).onChange(of: request) { _, _ in focused = true }
        } else {
            content
        }
    }
}
