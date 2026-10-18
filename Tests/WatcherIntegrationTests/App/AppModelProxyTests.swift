import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Starting the proxy from the window: a failed start stays visible until a retry.
@MainActor
@Suite(.timeLimit(.minutes(1)), .tags(.integration))
struct AppModelProxyTests {
    /// A port that is already taken leaves a visible error and a retry, not a silent toolbar.
    @Test(.tags(.network))
    func proxyStartFailureIsShownUntilRetry() async throws {
        let first = try Self.modelOnARealEngine()
        let port = try await first.engine.start(port: 0)
        let model: AppModel
        do {
            model = try modelPinned(to: port)
        } catch {
            try? await first.engine.stop()
            throw error
        }

        model.proxy.toggleRunning()
        #expect(model.proxy.isSwitchingProxy, "starting shows progress")
        model.proxy.toggleRunning() // a second click while starting is ignored
        #expect(await eventually { !model.proxy.isSwitchingProxy })
        #expect(!model.proxy.isRunning)
        #expect(model.proxy.proxyError != nil)
        #expect(model.notices.notice?.kind == .error)

        try await first.engine.stop()
        model.proxy.toggleRunning()
        #expect(model.proxy.proxyError == nil, "a new attempt clears the old error")
        #expect(await eventually { !model.proxy.isSwitchingProxy })
        #expect(model.proxy.isRunning)
        #expect(model.proxy.proxyError == nil)
        model.proxy.toggleRunning()
        #expect(await eventually { !model.proxy.isSwitchingProxy && !model.proxy.isRunning })
    }

    @Test(arguments: [1, 65535])
    func theFirstAndLastPortsAreValid(port: Int) {
        #expect(PortRange.isValid(port))
    }

    /// A model that must start on `port` instead of picking a free one.
    private func modelPinned(to port: Int) throws -> AppModel {
        let model = try Self.modelOnARealEngine()
        var settings = model.engine.settings.value
        settings.port = port; settings.autoSelectPort = false
        try model.engine.settings.replace(with: settings)
        model.settings.value = settings
        return model
    }

    /// A model whose proxy really listens, on an engine that keeps its files in memory.
    private static func modelOnARealEngine() throws -> AppModel {
        let engine = try WatcherEngine.inMemory()
        return try AppModel(dependencies: .test(engine: engine, runner: engine))
    }
}
