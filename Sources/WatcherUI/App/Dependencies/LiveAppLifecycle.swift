import AppKit

enum LiveAppLifecycle {
    static let onTerminate: OnTerminate = { handler in
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
