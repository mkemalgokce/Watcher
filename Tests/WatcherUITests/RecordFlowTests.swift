import Foundation
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI
import XCTest

/// Record starts the proxy and Pause stops it; the system proxy follows without freezing the window.
@MainActor
final class RecordFlowTests: XCTestCase {
    /// Records each networksetup call and whether it ran on the main thread; answers like a Mac with one service.
    private final class FakeNetworkSetup: @unchecked Sendable {
        /// A real write takes about 0.1 s; pass that to check the window does not wait for it.
        let delay: TimeInterval
        init(delay: TimeInterval = 0) {
            self.delay = delay
        }

        private let lock = NSLock()
        private var calls: [(arguments: [String], onMain: Bool)] = []

        var arguments: [[String]] {
            lock.withLock { calls.map(\.arguments) }
        }

        var anyOnMain: Bool {
            lock.withLock { calls.contains { $0.onMain } }
        }

        func run(_ arguments: [String]) -> String {
            lock.withLock { calls.append((arguments, Thread.isMainThread)) }
            Thread.sleep(forTimeInterval: delay)
            switch arguments.first {
            case "-listallnetworkservices": return "An asterisk (*) denotes a disabled service.\nWi-Fi\n"
            case "-getwebproxy", "-getsecurewebproxy": return "Enabled: No\nServer: \nPort: 0\n"
            default: return ""
            }
        }
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let held = await eventually(timeout: timeout) { condition() }
        XCTAssertTrue(held, "timed out", file: file, line: line)
    }

    private func makeModel(_ fake: FakeNetworkSetup) -> AppModel {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString).json")
        let model = AppModel(listening: false, systemProxy: SystemProxy(run: { fake.run($0) }, backupURL: backup))
        model.settings.port = PortFinder.firstAvailable(from: 21000) ?? 29998
        model.settings.autoSystemProxy = true
        return model
    }

    func testRecordTurnsTheSystemProxyOnOffTheMainThreadAtTheBoundPort() async {
        let fake = FakeNetworkSetup()
        let model = makeModel(fake)

        model.toggleRunning()
        await waitUntil(model.isRunning && model.systemProxyOn && !model.isSwitchingProxy)

        let port = String(model.engine.boundPort ?? -1)
        let expected = ["-setwebproxy", "Wi-Fi", "127.0.0.1", port]
        XCTAssertTrue(fake.arguments.contains(expected), "uses the port actually bound")
        XCTAssertFalse(fake.anyOnMain, "networksetup must not block the window")

        model.toggleRunning()
        await waitUntil(!model.isRunning && !model.systemProxyOn && !model.isSwitchingProxy)
        XCTAssertTrue(fake.arguments.contains(["-setwebproxystate", "Wi-Fi", "off"]), "pausing restores the original")
        XCTAssertFalse(fake.anyOnMain)
    }

    /// Record and Pause answer at once; the slow system-proxy switch finishes in the background, and the proxy keeps
    /// serving until the Mac's own settings are back so no request hits a closed port.
    func testRecordAndPauseDoNotWaitForTheSystemProxy() async {
        let fake = FakeNetworkSetup(delay: 0.1)
        let model = makeModel(fake)

        var started = Date()
        model.toggleRunning()
        await waitUntil(model.isRunning && !model.isSwitchingProxy)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2, "Record must not wait for networksetup")
        await waitUntil(model.systemProxyOn, timeout: 10)

        started = Date()
        model.toggleRunning()
        await waitUntil(!model.isRunning && !model.isSwitchingProxy)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2, "Pause must not wait for networksetup")
        XCTAssertTrue(model.engine.isRunning, "the proxy serves until the original settings are back")
        await waitUntil(!model.systemProxyOn && !model.engine.isRunning, timeout: 10)

        model.toggleRunning() // a new Record waits for the pending switch instead of racing it
        await waitUntil(model.isRunning && model.systemProxyOn, timeout: 10)
        model.toggleRunning()
        await waitUntil(!model.systemProxyOn && !model.engine.isRunning, timeout: 10)
    }

    func testTheProxyDoesNotStartUntilRecordIsPressed() async {
        let model = makeModel(FakeNetworkSetup())
        model.onboardingDone = true
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.statusLine, "Not recording · 0 requests")
    }
}
