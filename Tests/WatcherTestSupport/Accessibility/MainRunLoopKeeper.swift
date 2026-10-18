import CoreFoundation

/// Keeps the main run loop running for windows driven in-process. Swift Testing drains the main actor from one
/// CFRunLoopRun and exits the process when it returns, but AppKit stops the main run loop whenever accessibility
/// presses a control. Run from a run-loop block, outside the main queue, a nested run still drains the main queue, and
/// a stop only ends that run, which starts again.
@MainActor
enum MainRunLoopKeeper {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
            while true {
                CFRunLoopRun()
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
