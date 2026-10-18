import AppKit
import WatcherUI

/// A clipboard that lives in memory: tests put text on it and read back what was copied.
@MainActor
public final class ClipboardSpy: Clipboard {
    public private(set) var text: String?
    public private(set) var images: [NSImage] = []

    public init(text: String? = nil) {
        self.text = text
    }

    public func string() -> String? {
        text
    }

    public func setString(_ text: String) {
        self.text = text
    }

    public func setImage(_ image: NSImage) {
        images.append(image)
    }
}
