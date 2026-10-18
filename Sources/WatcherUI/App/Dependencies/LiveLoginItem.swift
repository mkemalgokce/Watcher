import ServiceManagement

extension LoginItem {
    /// The app's own login item; registering works only in the packaged Watcher.app.
    static let live = LoginItem(
        isEnabled: { SMAppService.mainApp.status == .enabled },
        setEnabled: { enabled in try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    )

    /// Previews: always off, and changes go nowhere.
    static let inert = LoginItem(isEnabled: { false }, setEnabled: { _ in })
}
