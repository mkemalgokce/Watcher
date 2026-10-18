import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Starting the proxy from the window: invalid ports are refused and a failed start stays visible until a retry.
@MainActor
@Suite(.timeLimit(.minutes(1)), .tags(.integration))
struct AppModelProxyTests {
    /// A port that is already taken leaves a visible error and a retry, not a silent toolbar.
    @Test(.tags(.network))
    func proxyStartFailureIsShownUntilRetry() async throws {
        let first = AppModel(listening: false)
        let port = try await first.engine.start(port: 0)
        let model: AppModel
        do {
            model = try modelPinned(to: port)
        } catch {
            try? await first.engine.stop()
            throw error
        }

        model.toggleRunning()
        #expect(model.isSwitchingProxy, "starting shows progress")
        model.toggleRunning() // a second click while starting is ignored
        #expect(await eventually { !model.isSwitchingProxy })
        #expect(!model.isRunning)
        #expect(model.proxyError != nil)
        #expect(model.notices.notice?.kind == .error)

        try await first.engine.stop()
        model.toggleRunning()
        #expect(model.proxyError == nil, "a new attempt clears the old error")
        #expect(await eventually { !model.isSwitchingProxy })
        #expect(model.isRunning)
        #expect(model.proxyError == nil)
        model.toggleRunning()
        #expect(await eventually { !model.isSwitchingProxy && !model.isRunning })
    }

    @Test(arguments: [0, -1, 65536])
    func invalidPortIsRefusedWithoutTryingToStart(port: Int) {
        let model = AppModel(listening: false)
        model.settings.port = port
        model.toggleRunning()
        #expect(!model.isSwitchingProxy)
        #expect(model.proxyError?.contains("not valid") == true)
    }

    @Test(arguments: [1, 65535])
    func theFirstAndLastPortsAreValid(port: Int) {
        #expect(PortRange.isValid(port))
    }

    /// A model that must start on `port` instead of picking a free one.
    private func modelPinned(to port: Int) throws -> AppModel {
        let model = AppModel(listening: false)
        var settings = model.engine.settings.value
        settings.port = port; settings.autoSelectPort = false
        try model.engine.settings.replace(with: settings)
        model.settings = settings
        return model
    }
}
