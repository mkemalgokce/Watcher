import AppKit

/// Where Copy writes and New Request from cURL reads.
@MainActor
public protocol Clipboard: AnyObject {
    func string() -> String?
    func setString(_ text: String)
    func setImage(_ image: NSImage)
}
