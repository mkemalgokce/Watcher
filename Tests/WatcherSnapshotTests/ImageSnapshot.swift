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

    @MainActor
    static func verify(
        _ view: some View,
        size: CGSize,
        named name: String,
        filePath: StaticString = #filePath,
        testName: String = #function,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(origin: .zero, size: size)
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
