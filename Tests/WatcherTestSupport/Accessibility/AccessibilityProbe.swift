import AppKit
import ApplicationServices
import SwiftUI

/// Whether accessibility can drive this process's windows: it must be trusted, and the service must hand out real
/// windows (it has been seen to answer with the application element in a loop). Checked once per process, because
/// every nested suite evaluates the condition it inherits.
@MainActor
public enum AccessibilityProbe {
    private static var verdict: Bool?

    public static func isUsable() async -> Bool {
        if let verdict {
            return verdict
        }
        let usable = await probe()
        verdict = usable
        return usable
    }

    private static func probe() async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        // The test runner is not launched as an app, so it does not answer accessibility requests until it becomes one.
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        MainRunLoopKeeper.install()
        let probe = TestWindow(showing: Text("Accessibility check"), width: 200, height: 100)
        defer { probe.close() }
        await settle()
        return AccessibilityAPI.firstWindowRole() == "AXWindow"
    }
}
