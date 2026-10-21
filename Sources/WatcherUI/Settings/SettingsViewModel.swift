import Observation
import WatcherCore

/// What the General settings pane says about the listener and the port, the login item macOS owns, and the website
/// icon switch.
@MainActor @Observable
final class SettingsViewModel {
    enum Status: Equatable { case listening, stopped, failed }

    enum PortWarning: Equatable {
        case invalid, needsAdministrator

        var message: String {
            switch self {
            case .invalid: "Use a port from 1 to 65535. Ports below 1024 need administrator rights."
            case .needsAdministrator: "Ports below 1024 need administrator rights; the proxy may fail to start."
            }
        }
    }

    /// Read back from macOS after every change, since the change can be refused.
    var opensAtLogin: Bool {
        get { loginEnabled }
        set { setOpensAtLogin(newValue) }
    }

    /// Whether Watcher looks for a newer version by itself; read back after every change, as the updater owns it.
    var checksForUpdates: Bool {
        get { automaticChecks }
        set { setChecksForUpdates(newValue) }
    }

    var offersUpdates: Bool {
        updater != nil
    }

    var showsWebsiteIcons: Bool {
        didSet { preferences.websiteIconsEnabled = showsWebsiteIcons }
    }

    private var loginEnabled: Bool
    private var automaticChecks: Bool
    @ObservationIgnored private let proxy: ProxyController
    @ObservationIgnored private let settings: SettingsEditor
    @ObservationIgnored private let preferences: any Preferences
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private let updater: AppUpdater?
    @ObservationIgnored private let notices: NoticeCenter

    init(
        proxy: ProxyController,
        settings: SettingsEditor,
        preferences: any Preferences,
        loginItem: LoginItem,
        updater: AppUpdater?,
        notices: NoticeCenter
    ) {
        self.proxy = proxy; self.settings = settings; self.preferences = preferences
        self.loginItem = loginItem; self.updater = updater; self.notices = notices
        loginEnabled = loginItem.isEnabled()
        automaticChecks = updater?.checksAutomatically() ?? false
        showsWebsiteIcons = preferences.websiteIconsEnabled
    }

    var status: Status {
        proxy.isRunning ? .listening : proxy.proxyError == nil ? .stopped : .failed
    }

    var statusText: String {
        switch status {
        case .listening: "Listening on 127.0.0.1:\(String(proxy.port))"
        case .stopped: "Stopped"
        case .failed: "Failed to start"
        }
    }

    var portWarning: PortWarning? {
        let port = settings.port
        if !PortRange.isValid(port) {
            return .invalid
        }
        return port < 1024 ? .needsAdministrator : nil
    }

    private func setChecksForUpdates(_ enabled: Bool) {
        updater?.setChecksAutomatically(enabled)
        automaticChecks = updater?.checksAutomatically() ?? false
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do { try loginItem.setEnabled(enabled) } catch {
            let message = "Cannot change the login item: \(error.localizedDescription). "
                + "This works only in the packaged Watcher.app."
            notices.notify(message, .error)
        }
        loginEnabled = loginItem.isEnabled()
    }
}
