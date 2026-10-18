import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ProxyControllerTests {
    /// Switches that fail, repeat or overlap.
    @MainActor
    struct Edges {
        private let log = LockedBox<[String]>([])
        private let notices = NoticeCenter.silent()

        private func controller(
            systemProxy: SystemProxySpy, autoSystemProxy: Bool = false
        ) -> (ProxyController, ProxyRunnerStub) {
            let runner = ProxyRunnerStub(log: log)
            var settings = WatcherSettings()
            settings.autoSystemProxy = autoSystemProxy
            let frozen = settings
            return (ProxyController(runner: runner, systemProxy: systemProxy, notices: notices) { frozen }, runner)
        }

        @Test
        func aStartWhoseSystemProxySwitchFailsKeepsRecordingAndSaysWhatFailed() async {
            let systemProxy = SystemProxySpy(log: log)
            systemProxy.failFromNowOn()
            let (proxy, _) = controller(systemProxy: systemProxy, autoSystemProxy: true)
            proxy.toggleRunning()
            #expect(await eventually { notices.notice?.kind == .error })
            #expect(notices.notice?.message.hasPrefix("Cannot change the system proxy") == true)
            #expect(proxy.isRunning)
            #expect(!proxy.systemProxyOn)
            #expect(proxy.state == .running)
        }

        @Test
        func switchingTheSystemProxyOffWhileItIsOffLeavesItOffAndSaysSo() async {
            let systemProxy = SystemProxySpy(log: log)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.setSystemProxy(false)
            let message = "System proxy off. Your original settings are back."
            #expect(await eventually { notices.notice?.message == message })
            #expect(!proxy.systemProxyOn)
        }

        @Test
        func aFailingRestoreAtLaunchOrQuitIsSwallowed() async {
            let systemProxy = SystemProxySpy(hasPendingRestore: true, log: log)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.setSystemProxy(true)
            #expect(await eventually { proxy.systemProxyOn })
            systemProxy.failFromNowOn()
            proxy.restoreLeftoverSystemProxy()
            proxy.applicationWillTerminate()
            #expect(proxy.systemProxyOn, "nothing is assumed about a switch that failed")
            #expect(notices.notice?.kind == .success)
        }

        @Test
        func pausingWaitsForTheSystemProxySwitchThatRecordStarted() async {
            let gate = DispatchSemaphore(value: 0)
            let systemProxy = SystemProxySpy(log: log, enableGate: gate)
            let (proxy, _) = controller(systemProxy: systemProxy, autoSystemProxy: true)
            proxy.toggleRunning()
            #expect(await eventually { proxy.isRunning && !proxy.isSwitchingProxy })
            proxy.toggleRunning()
            #expect(await eventually { systemProxy.enableCallsStarted == 1 })
            #expect(log.value == ["start 9090"], "the enable is still held, so pause has not begun")
            gate.signal()
            #expect(await eventually { log.value == ["start 9090", "enable 9123", "disable", "stop"] })
            #expect(await eventually { !proxy.isSwitchingProxy })
            #expect(!proxy.systemProxyOn)
        }
    }
}
