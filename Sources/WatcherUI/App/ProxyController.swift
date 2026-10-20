import Observation
import WatcherCore

/// Record and Pause, and the Mac's own proxy setting that follows them. Recording is shown at once; the slow
/// system-proxy switch runs in the background, and the next Record or Pause waits for it.
@MainActor @Observable
final class ProxyController {
    private(set) var isRunning = false
    /// Set while the proxy is starting or stopping, so the toolbar and empty list can say so instead of looking frozen.
    private(set) var isSwitchingProxy = false
    /// Why the last start failed; shown in the empty list until the next attempt.
    var proxyError: String?
    private(set) var systemProxyOn = false

    @ObservationIgnored private var systemProxySwitch: Task<Void, Never>?
    /// What the Mac's proxy will be once every queued switch has run; a click flips this, not the state in between.
    private(set) var systemProxyTarget = false
    @ObservationIgnored private var queuedSwitches = 0
    @ObservationIgnored private let runner: any ProxyRunning
    @ObservationIgnored private let systemProxy: any SystemProxying
    @ObservationIgnored private let notices: NoticeCenter
    @ObservationIgnored private let settings: () -> WatcherSettings

    init(
        runner: any ProxyRunning,
        systemProxy: any SystemProxying,
        notices: NoticeCenter,
        settings: @escaping () -> WatcherSettings
    ) {
        self.runner = runner; self.systemProxy = systemProxy; self.notices = notices; self.settings = settings
    }

    enum State: Equatable {
        case stopped, switching, running, failed
    }

    /// One value for the indicators that tint by what the proxy is doing.
    var state: State {
        if proxyError != nil {
            return .failed
        }
        if isSwitchingProxy {
            return .switching
        }
        return isRunning ? .running : .stopped
    }

    /// A system-proxy switch needs a listening proxy that is not itself starting or stopping.
    var canSwitchSystemProxy: Bool {
        isRunning && !isSwitchingProxy
    }

    /// The port the proxy listens on: the one it bound while running, otherwise the configured one.
    var port: Int {
        runner.boundPort ?? settings().port
    }

    /// The line under the window title: starting, listening (with the address), stopped, or that starting failed.
    func status(listing count: String) -> String {
        if isSwitchingProxy {
            return isRunning ? "Stopping…" : "Starting…"
        }
        if proxyError != nil {
            return "Failed to start · see Settings"
        }
        if isRunning {
            return "Recording on 127.0.0.1:\(String(port)) · \(count)"
        }
        return "Not recording · \(count)"
    }

    func toggleRunning() {
        guard !isSwitchingProxy else { return }
        if isRunning {
            switchProxy()
        } else {
            startRecording()
        }
    }

    /// Starts the proxy when it is off; unlike `toggleRunning` it never pauses a proxy that is already on.
    func startRecording() {
        guard !isRunning, !isSwitchingProxy else { return }
        let port = settings().port
        if !PortRange.isValid(port) {
            let error = "Port \(port) is not valid. Choose a port from 1 to 65535 in Settings."
            proxyError = error
            notices.notify(error, .error)
            return
        }
        switchProxy()
    }

    private func switchProxy() {
        isSwitchingProxy = true
        proxyError = nil
        // At the click, not after the queued system-proxy switch: that can take seconds, the proxy keeps carrying traffic
        // until it is done, and the window already says paused.
        if isRunning {
            runner.isRecording = false
        }
        let pending = systemProxySwitch
        Task {
            defer { isSwitchingProxy = false }
            await pending?.value
            if isRunning {
                await pause()
            } else {
                await record()
            }
        }
    }

    func setSystemProxy(_ enabled: Bool) {
        queueSystemProxy(enabled)
    }

    func toggleSystemProxy() {
        setSystemProxy(!systemProxyTarget)
    }

    /// A proxy setting left behind by a crashed run would cut the Mac off from the network.
    func restoreLeftoverSystemProxy() {
        if systemProxy.hasPendingRestore {
            try? systemProxy.disable()
        }
    }

    func applicationWillTerminate() {
        if systemProxyOn {
            try? systemProxy.disable()
        }
    }

    private func record() async {
        let settings = settings()
        // Before the listener opens, so the first request is not dropped.
        runner.isRecording = true
        do {
            _ = try await runner.start(port: settings.port)
            isRunning = true
            if settings.autoSystemProxy {
                queueSystemProxy(true)
            }
            notices.notify("Recording on 127.0.0.1:\(port)", .success)
        } catch {
            isRunning = runner.isRunning
            let message = "Cannot start the proxy: \(error). Another app may be using port \(settings.port); "
                + "pick a different port in Settings."
            proxyError = message
            notices.notify(message, .error, action: NoticeAction(title: "Try Again") { [weak self] in
                self?.startRecording()
            })
        }
    }

    /// Mac traffic still points here until the original settings are back, so with the system proxy on the proxy
    /// stops only after that.
    private func pause() async {
        isRunning = false
        let runner = runner
        if systemProxyOn || systemProxyTarget {
            queueSystemProxy(false, then: { try? await runner.stop() })
        } else {
            try? await runner.stop()
        }
        notices.notify("Recording paused; the proxy is off")
    }

    /// Switches run one after the other in the order asked, so the last click decides where the setting ends up.
    private func queueSystemProxy(_ enable: Bool, then followUp: (@Sendable () async -> Void)? = nil) {
        systemProxyTarget = enable
        queuedSwitches += 1
        let previous = systemProxySwitch
        systemProxySwitch = Task {
            await previous?.value
            await switchSystemProxy(enable)
            queuedSwitches -= 1
            if queuedSwitches == 0 {
                systemProxyTarget = systemProxyOn
            }
            await followUp?()
        }
    }

    /// networksetup runs once per setting and service, so it runs off the main thread to keep the window responsive.
    private func switchSystemProxy(_ enable: Bool) async {
        let proxy = systemProxy, port = port
        do {
            try await Task.detached {
                if enable {
                    try proxy.enable(port: port)
                } else {
                    try proxy.disable()
                }
            }.value
            systemProxyOn = enable
            let message = enable
                ? "System proxy on. Mac traffic now goes through Watcher."
                : "System proxy off. Your original settings are back."
            notices.notify(message, .success)
        } catch {
            let message = "Cannot change the system proxy: \(error). "
                + "macOS may need your permission in System Settings → Privacy & Security."
            notices.notify(message, .error)
        }
    }
}
