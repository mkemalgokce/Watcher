import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Record and Pause, the Mac's own proxy setting, and the line under the window title.
@MainActor
@Suite(.tags(.unit))
struct ProxyControllerTests {
    private let log = LockedBox<[String]>([])
    private let notices = NoticeCenter(sleep: sleepUntilCancelled) { _ in }
    private var settings = WatcherSettings()

    private func controller(
        runner: ProxyRunnerStub? = nil,
        systemProxy: SystemProxySpy? = nil,
        autoSystemProxy: Bool = false,
        port: Int = 9090
    ) -> (ProxyController, ProxyRunnerStub, SystemProxySpy) {
        let runner = runner ?? ProxyRunnerStub(log: log)
        let systemProxy = systemProxy ?? SystemProxySpy(log: log)
        var settings = settings
        settings.port = port
        settings.autoSystemProxy = autoSystemProxy
        let frozen = settings
        let controller = ProxyController(runner: runner, systemProxy: systemProxy, notices: notices) { frozen }
        return (controller, runner, systemProxy)
    }

    @Test(arguments: [0, -1, 65536])
    func anInvalidPortIsRefusedWithoutStarting(port: Int) {
        let (proxy, runner, _) = controller(port: port)
        proxy.toggleRunning()
        #expect(!proxy.isSwitchingProxy)
        #expect(runner.calls.isEmpty)
        #expect(proxy.proxyError == "Port \(port) is not valid. Choose a port from 1 to 65535 in Settings.")
        #expect(notices.notice?.kind == .error)
    }

    @Test
    func recordStartsOnTheConfiguredPortAndSaysWhereItListens() async {
        let (proxy, runner, _) = controller(port: 9090)
        proxy.toggleRunning()
        #expect(proxy.isSwitchingProxy, "starting shows progress")
        #expect(proxy.status(listing: "0 requests") == "Starting…")
        #expect(await eventually { !proxy.isSwitchingProxy })
        #expect(proxy.isRunning)
        #expect(runner.calls == ["start 9090"])
        #expect(notices.notice?.message == "Recording on 127.0.0.1:9123")
        #expect(proxy.port == 9123, "the bound port wins over the configured one")
        #expect(proxy.status(listing: "2 requests") == "Recording on 127.0.0.1:9123 · 2 requests")
    }

    @Test
    func aSecondClickWhileStartingIsIgnored() async {
        let (proxy, runner, _) = controller()
        proxy.toggleRunning()
        proxy.toggleRunning()
        #expect(await eventually { !proxy.isSwitchingProxy })
        #expect(runner.calls.count == 1)
    }

    @Test
    func aFailedStartIsShownUntilTheNextAttempt() async {
        let runner = ProxyRunnerStub(log: log)
        runner.failStarting()
        let (proxy, _, _) = controller(runner: runner, port: 9090)
        proxy.toggleRunning()
        #expect(await eventually { !proxy.isSwitchingProxy })
        #expect(!proxy.isRunning)
        let error = "Cannot start the proxy: address in use. Another app may be using port 9090; "
            + "pick a different port in Settings."
        #expect(proxy.proxyError == error)
        #expect(notices.notice?.message == error)
        #expect(proxy.status(listing: "0 requests") == "Failed to start · see Settings")

        runner.failStarting(nil)
        proxy.toggleRunning()
        #expect(proxy.proxyError == nil, "a new attempt clears the old error")
        #expect(await eventually { proxy.isRunning })
    }

    @Test
    func pauseStopsAtOnceWhenTheSystemProxyIsOff() async {
        let (proxy, runner, systemProxy) = controller()
        proxy.toggleRunning()
        #expect(await eventually { proxy.isRunning && !proxy.isSwitchingProxy })
        proxy.toggleRunning()
        #expect(proxy.status(listing: "0 requests") == "Stopping…")
        #expect(await eventually { !proxy.isSwitchingProxy })
        #expect(!proxy.isRunning)
        #expect(runner.calls == ["start 9090", "stop"])
        #expect(systemProxy.calls.isEmpty)
        #expect(notices.notice?.message == "Recording paused; the proxy is off")
        #expect(proxy.status(listing: "3 requests") == "Not recording · 3 requests")
    }

    @Test
    func withTheAutomaticSystemProxyRecordTurnsItOnAtTheBoundPort() async {
        let (proxy, _, systemProxy) = controller(autoSystemProxy: true)
        proxy.toggleRunning()
        #expect(await eventually { proxy.systemProxyOn })
        #expect(systemProxy.calls == ["enable 9123"])
        #expect(notices.notice?.message == "System proxy on. Mac traffic now goes through Watcher.")
    }

    @Test
    func pauseRestoresTheSystemProxyBeforeStoppingTheProxy() async {
        let (proxy, _, _) = controller(autoSystemProxy: true)
        proxy.toggleRunning()
        #expect(await eventually { proxy.systemProxyOn && !proxy.isSwitchingProxy })
        proxy.toggleRunning()
        #expect(await eventually { !proxy.isSwitchingProxy })
        #expect(!proxy.isRunning, "shown as stopped at once")
        #expect(await eventually { log.value.last == "stop" })
        #expect(log.value == ["start 9090", "enable 9123", "disable", "stop"])
        #expect(!proxy.systemProxyOn)
    }

    @Test
    func theSystemProxyCanBeSwitchedByHand() async {
        let (proxy, _, systemProxy) = controller(port: 9090)
        proxy.setSystemProxy(true)
        #expect(await eventually { proxy.systemProxyOn })
        #expect(systemProxy.calls == ["enable 9090"])
        proxy.setSystemProxy(false)
        #expect(await eventually { !proxy.systemProxyOn })
        #expect(notices.notice?.message == "System proxy off. Your original settings are back.")
    }

    @Test
    func aFailedSystemProxyChangeIsReportedAndChangesNothing() async {
        let (proxy, _, systemProxy) = controller()
        systemProxy.failFromNowOn()
        proxy.setSystemProxy(true)
        #expect(await eventually { notices.notice?.kind == .error })
        #expect(notices.notice?.message.hasPrefix("Cannot change the system proxy") == true)
        #expect(!proxy.systemProxyOn)
    }

    @Test(arguments: [true, false])
    func aProxyLeftOnByACrashIsRestoredAtLaunch(pending: Bool) {
        let systemProxy = SystemProxySpy(hasPendingRestore: pending, log: log)
        let (proxy, _, _) = controller(systemProxy: systemProxy)
        proxy.restoreLeftoverSystemProxy()
        #expect(systemProxy.calls == (pending ? ["disable"] : []))
    }

    @Test
    func quittingTurnsTheSystemProxyOffOnlyWhenItIsOn() async {
        let (proxy, _, systemProxy) = controller()
        proxy.applicationWillTerminate()
        #expect(systemProxy.calls.isEmpty)
        proxy.setSystemProxy(true)
        #expect(await eventually { proxy.systemProxyOn })
        proxy.applicationWillTerminate()
        #expect(systemProxy.calls == ["enable 9090", "disable"])
    }

    @Test
    func theConfiguredPortIsShownUntilOneIsBound() {
        let (proxy, _, _) = controller(port: 8888)
        #expect(proxy.port == 8888)
    }
}
