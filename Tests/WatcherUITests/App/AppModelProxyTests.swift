import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Starting the proxy from the window: invalid ports are refused and a failed start stays visible until a retry.
@MainActor
struct AppModelProxyTests {
    /// Integration: a port that is already taken leaves a visible error and a retry, not a silent toolbar.
    @Test(.tags(.network))
    func proxyStartFailureIsShownUntilRetry() async throws {
        let first = AppModel(listening: false)
        let port = try await first.engine.start(port: 0)
        defer { Task { try? await first.engine.stop() } }

        let model = AppModel(listening: false)
        var settings = model.engine.settings.value
        settings.port = port; settings.autoSelectPort = false
        try model.engine.settings.replace(with: settings)
        model.settings = settings

        model.toggleRunning()
        #expect(model.isSwitchingProxy, "starting shows progress")
        model.toggleRunning() // a second click while starting is ignored
        #expect(await eventually { !model.isSwitchingProxy })
        #expect(!model.isRunning)
        #expect(model.proxyError != nil)
        #expect(model.notice?.kind == .error)

        try await first.engine.stop()
        model.toggleRunning()
        #expect(model.proxyError == nil, "a new attempt clears the old error")
        #expect(await eventually { !model.isSwitchingProxy })
        #expect(model.isRunning)
        #expect(model.proxyError == nil)
        model.toggleRunning()
        #expect(await eventually { !model.isSwitchingProxy && !model.isRunning })
    }

    @Test
    func invalidPortIsRefusedWithoutTryingToStart() {
        let model = AppModel(listening: false)
        for port in [0, -1, 65536] {
            model.settings.port = port
            model.toggleRunning()
            #expect(!model.isSwitchingProxy, "\(port)")
            #expect(model.proxyError?.contains("not valid") == true, "\(port)")
        }
        #expect(PortRange.isValid(1)); #expect(PortRange.isValid(65535))
    }
}
