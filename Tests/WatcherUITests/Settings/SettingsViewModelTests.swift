import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The General settings pane: what it says about the listener and the port, the login item macOS owns, and the
/// website icon switch.
@MainActor
@Suite(.tags(.unit))
struct SettingsViewModelTests {
    private let runner = ProxyRunnerStub(boundPort: 9123)

    private func model(
        loginItem: LoginItemStub? = nil,
        preferences: PreferencesFake? = nil,
        updater: UpdaterStub? = nil
    ) throws -> AppModel {
        try AppModel(dependencies: .test(
            preferences: preferences, runner: runner, loginItem: loginItem, updater: updater
        ))
    }

    @Test
    func theStatusFollowsTheProxy() async throws {
        let model = try model()
        let pane = model.settingsPane
        #expect(pane.status == .stopped)
        #expect(pane.statusText == "Stopped")

        model.proxy.toggleRunning()
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
        #expect(pane.status == .listening)
        #expect(pane.statusText == "Listening on 127.0.0.1:9123")

        model.proxy.toggleRunning()
        #expect(await eventually { !model.proxy.isSwitchingProxy })
        runner.failStarting()
        model.proxy.toggleRunning()
        #expect(await eventually { model.proxy.proxyError != nil })
        #expect(pane.status == .failed)
        #expect(pane.statusText == "Failed to start")
    }

    @Test(arguments: [
        (0, SettingsViewModel.PortWarning.invalid),
        (-1, .invalid),
        (65536, .invalid),
        (1, .needsAdministrator),
        (1023, .needsAdministrator),
    ])
    func aPortThatCannotWorkIsExplained(port: Int, expected: SettingsViewModel.PortWarning) throws {
        let model = try model()
        model.settings.port = port
        #expect(model.settingsPane.portWarning == expected)
    }

    @Test(arguments: [1024, 9090, 65535])
    func anOrdinaryPortNeedsNoWarning(port: Int) throws {
        let model = try model()
        model.settings.port = port
        #expect(model.settingsPane.portWarning == nil)
    }

    @Test
    func eachWarningSaysWhatToDo() {
        #expect(SettingsViewModel.PortWarning.invalid.message
            == "Use a port from 1 to 65535. Ports below 1024 need administrator rights.")
        #expect(SettingsViewModel.PortWarning.needsAdministrator.message
            == "Ports below 1024 need administrator rights; the proxy may fail to start.")
    }

    @Test(arguments: [true, false])
    func theLoginItemIsReadFromTheMac(enabled: Bool) throws {
        #expect(try model(loginItem: LoginItemStub(isEnabled: enabled)).settingsPane.opensAtLogin == enabled)
    }

    @Test
    func switchingTheLoginItemChangesItOnTheMac() throws {
        let item = LoginItemStub()
        let pane = try model(loginItem: item).settingsPane
        pane.opensAtLogin = true
        #expect(item.isEnabled)
        #expect(pane.opensAtLogin)
        pane.opensAtLogin = false
        #expect(!item.isEnabled)
    }

    @Test
    func aRefusedLoginItemChangeIsReportedAndTheSwitchShowsTheMacsState() throws {
        let model = try model(loginItem: LoginItemStub(isEnabled: false, failing: true))
        model.settingsPane.opensAtLogin = true
        #expect(!model.settingsPane.opensAtLogin)
        #expect(model.notices.notice?.kind == .error)
        #expect(model.notices.notice?.message
            == "Cannot change the login item: not a bundled app. This works only in the packaged Watcher.app.")
    }

    @Test
    func updateSettingsAreOfferedOnlyWhereThereIsAnUpdater() throws {
        #expect(try !model().settingsPane.offersUpdates)
        #expect(try model(updater: UpdaterStub()).settingsPane.offersUpdates)
    }

    @Test(arguments: [true, false])
    func automaticChecksAreReadFromTheUpdater(enabled: Bool) throws {
        let pane = try model(updater: UpdaterStub(checksAutomatically: enabled)).settingsPane
        #expect(pane.checksForUpdates == enabled)
    }

    @Test
    func switchingAutomaticChecksTellsTheUpdater() throws {
        let updater = UpdaterStub(checksAutomatically: false)
        let pane = try model(updater: updater).settingsPane
        pane.checksForUpdates = true
        #expect(updater.checksAutomatically)
        #expect(pane.checksForUpdates)
        pane.checksForUpdates = false
        #expect(!updater.checksAutomatically)
        #expect(!pane.checksForUpdates)
    }

    @Test
    func automaticChecksReadAsOffWithoutAnUpdater() throws {
        let pane = try model().settingsPane
        pane.checksForUpdates = true
        #expect(!pane.checksForUpdates)
    }

    @Test
    func websiteIconsAreRememberedInThePreferences() throws {
        let preferences = PreferencesFake(["icons.websites": false])
        let pane = try model(preferences: preferences).settingsPane
        #expect(!pane.showsWebsiteIcons)
        pane.showsWebsiteIcons = true
        #expect(preferences.websiteIconsEnabled)
    }
}
