import AppKit

enum LiveAnnouncer {
    static let announce: Announce = { message in
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}
