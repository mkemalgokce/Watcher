import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Record starts the proxy and Pause stops it; the system proxy follows without freezing the window.
@MainActor
@Suite(.timeLimit(.minutes(1)), .serialized, .tags(.integration, .network))
struct RecordFlowTests {
    private let backup: TemporaryDirectory

    init() throws {
        backup = try TemporaryDirectory()
    }

    private func makeModel(_ networkSetup: NetworkSetupSpy) throws -> AppModel {
        let systemProxy = SystemProxy(run: { networkSetup.run($0) }, backupURL: backup.appending("backup.json"))
        let engine = try WatcherEngine.inMemory()
        let runner = AnyPortRunner(engine)
        let model = try AppModel(dependencies: .test(engine: engine, runner: runner, systemProxy: systemProxy))
        model.settings.autoSystemProxy = true
        return model
    }

    @Test
    func recordTurnsTheSystemProxyOnOffTheMainThreadAtTheBoundPort() async throws {
        let networkSetup = NetworkSetupSpy()
        let model = try makeModel(networkSetup)

        model.proxy.toggleRunning()
        let proxy = model.proxy
        #expect(await eventually { proxy.isRunning && proxy.systemProxyOn && !proxy.isSwitchingProxy })

        let port = String(model.engine.boundPort ?? -1)
        let expected = ["-setwebproxy", "Wi-Fi", "127.0.0.1", port]
        #expect(networkSetup.arguments.contains(expected), "uses the port actually bound")
        #expect(!networkSetup.anyOnMain, "networksetup must not block the window")

        model.proxy.toggleRunning()
        #expect(await eventually { !proxy.isRunning && !proxy.systemProxyOn && !proxy.isSwitchingProxy })
        #expect(
            networkSetup.arguments.contains(["-setwebproxystate", "Wi-Fi", "off"]),
            "pausing restores the original"
        )
        #expect(!networkSetup.anyOnMain)
    }

    /// Record and Pause answer at once; the slow system-proxy switch finishes in the background, and the proxy keeps
    /// serving until the Mac's own settings are back so no request hits a closed port.
    @Test
    func recordAndPauseDoNotWaitForTheSystemProxy() async throws {
        let networkSetup = NetworkSetupSpy()
        networkSetup.hold()
        let model = try makeModel(networkSetup)

        model.proxy.toggleRunning()
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
        #expect(!model.proxy.systemProxyOn, "networksetup is still blocked")
        networkSetup.release()
        #expect(await eventually(timeout: 10) { model.proxy.systemProxyOn })

        networkSetup.hold()
        model.proxy.toggleRunning()
        #expect(await eventually { !model.proxy.isRunning && !model.proxy.isSwitchingProxy })
        #expect(model.engine.isRunning, "the proxy serves until the original settings are back")
        networkSetup.release()
        #expect(await eventually(timeout: 10) { !model.proxy.systemProxyOn && !model.engine.isRunning })

        model.proxy.toggleRunning() // a new Record waits for the pending switch instead of racing it
        #expect(await eventually(timeout: 10) { model.proxy.isRunning && model.proxy.systemProxyOn })
        model.proxy.toggleRunning()
        #expect(await eventually(timeout: 10) { !model.proxy.systemProxyOn && !model.engine.isRunning })
    }
}
