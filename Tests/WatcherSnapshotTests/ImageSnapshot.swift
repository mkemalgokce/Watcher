import AppKit
import SnapshotTesting
import SwiftUI
import Testing

/// Image references differ between macOS releases, so each major version keeps its own under `__Snapshots__/macOS-<major>/`.
enum ImageSnapshot {
    static let osFolder = "macOS-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"

    /// Off when this macOS has no references next to the calling test file and the run may not record them
    /// (`SNAPSHOT_TESTING_RECORD=never`, as on CI).
    static func canRun(filePath: String = #filePath) -> Bool {
        let references = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__").appendingPathComponent(osFolder)
        return FileManager.default.fileExists(atPath: references.path)
            || ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] != "never"
    }

    private static let settleLimit: TimeInterval = 5

    /// Lets what a screen starts when it appears (formatting a body, comparing two responses) finish: runs the main
    /// loop until `isDone` holds and two renders in a row are identical, and records an issue after `settleLimit`.
    @MainActor
    private static func settle(
        _ view: NSView, until isDone: () -> Bool, sourceLocation: SourceLocation
    ) async {
        var previous: Data?
        let deadline = Date(timeIntervalSinceNow: settleLimit)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            let current = view.bitmapImageRepForCachingDisplay(in: view.bounds).flatMap { rep -> Data? in
                view.cacheDisplay(in: view.bounds, to: rep)
                return rep.representation(using: .tiff, properties: [:])
            }
            if isDone(), current != nil, current == previous {
                return
            }
            previous = current
        }
        Issue.record("The screen never settled.", sourceLocation: sourceLocation)
    }

    /// The size, language, time zone and animations every reference is rendered with.
    @MainActor
    private static func fixed(_ view: some View, size: CGSize) -> some View {
        view.frame(width: size.width, height: size.height)
            .background(.background)
            .environment(\.locale, locale)
            .environment(\.timeZone, timeZone)
            .transaction { $0.animation = nil }
    }

    static let timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    static let locale = Locale(identifier: "en_GB")

    /// One screen is drawn at a time, so the main actor keeps its time for the other suites' waits.
    private actor Turn {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            guard busy else { return busy = true }
            await withCheckedContinuation { waiting.append($0) }
        }

        func release() {
            waiting.isEmpty ? busy = false : waiting.removeFirst().resume()
        }
    }

    private static let turn = Turn()

    /// `until` holds once the work the screen starts has finished, such as a device scan.
    @MainActor
    static func verify(
        _ view: some View,
        size: CGSize,
        named name: String,
        appearance: NSAppearance.Name = .aqua,
        until isDone: () -> Bool = { true },
        filePath: StaticString = #filePath,
        testName: String = #function,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await turn.acquire()
        defer { Task { await turn.release() } }
        let host = NSHostingView(rootView: Self.fixed(view, size: size))
        // A scene toolbar makes table cells lose their environment when no scene hosts the view.
        host.sceneBridgingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false // ARC owns it; AppKit releasing it again on close() would crash
        host.appearance = NSAppearance(named: appearance)
        window.appearance = host.appearance
        window.contentView = host
        // Lists and tables draw nothing until their window is on screen; far outside every display, nobody sees it.
        window.setFrameOrigin(CGPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.useOpaqueSelections()
        await Self.settle(host, until: isDone, sourceLocation: sourceLocation)
        let file = URL(fileURLWithPath: "\(filePath)")
        let directory = file.deletingLastPathComponent().appendingPathComponent("__Snapshots__")
            .appendingPathComponent(osFolder).appendingPathComponent(file.deletingPathExtension().lastPathComponent)
        let failure = verifySnapshot(
            of: host,
            as: .image(precision: 0.99, perceptualPrecision: 0.98, size: size),
            named: name,
            snapshotDirectory: directory.path,
            file: filePath,
            testName: testName
        )
        if let failure {
            Issue.record(Comment(rawValue: failure), sourceLocation: sourceLocation)
        }
    }
}

private extension NSView {
    /// A source list paints its selection with a translucent material that an off-screen capture renders black.
    func useOpaqueSelections() {
        if let table = self as? NSTableView {
            table.selectionHighlightStyle = .regular
        }
        subviews.forEach { $0.useOpaqueSelections() }
    }
}
