import Foundation

/// How sizes and durations read everywhere in the window, so the list, inspector and status bar agree.
enum Format {
    /// "0 B" and "69 B" rather than ByteCountFormatter's "Zero KB" and "69 bytes": short enough for a narrow column, and an empty body reads as exactly empty.
    static func bytes(_ count: Int) -> String {
        count < 1000 ? "\(count) B" : ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 1 ? String(format: "%.0f ms", seconds * 1000) : String(format: "%.2f s", seconds)
    }
}
