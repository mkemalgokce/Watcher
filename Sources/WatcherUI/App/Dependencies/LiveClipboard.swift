import AppKit

/// A system pasteboard: the general one in the app, a private one in previews so they never touch the user's clipboard.
@MainActor
final class LiveClipboard: Clipboard {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func string() -> String? {
        pasteboard.string(forType: .string)
    }

    func setString(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func setImage(_ image: NSImage) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
