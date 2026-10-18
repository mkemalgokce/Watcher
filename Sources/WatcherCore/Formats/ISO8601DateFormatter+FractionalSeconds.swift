import Foundation

extension ISO8601DateFormatter {
    /// `2026-10-16T10:00:00.000Z`, as HAR and Charles sessions write their times.
    static func withFractionalSeconds() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
