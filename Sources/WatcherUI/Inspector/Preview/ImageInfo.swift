import Foundation
import WatcherCore

/// The words an image preview and the embedded-data list use for an image.
enum ImageInfo {
    /// "PNG" for `image/png`.
    static func typeLabel(mime: String) -> String {
        mime.replacingOccurrences(of: "image/", with: "").uppercased()
    }

    /// The type the response declared, else the one the bytes show.
    static func mime(declared: String?, data: Data) -> String? {
        declared ?? Base64Finder.imageMime(data)
    }

    /// "640 × 480 · PNG · 12 KB".
    static func summary(width: Int, height: Int, declaredMime: String?, data: Data) -> String {
        let type = typeLabel(mime: mime(declared: declaredMime, data: data) ?? "image")
        return "\(width) × \(height) · \(type) · \(Format.bytes(data.count))"
    }
}
