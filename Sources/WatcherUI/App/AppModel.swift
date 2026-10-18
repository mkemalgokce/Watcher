import AppKit
import Observation
import SwiftUI
import WatcherCore

/// Builds the window's view models from one set of dependencies and connects them; the proxy itself lives in
/// `WatcherEngine`.
@MainActor @Observable
public final class AppModel {
    typealias Sheet = WindowRouter.Sheet

    let engine: WatcherEngine
    @ObservationIgnored let clipboard: any Clipboard
    @ObservationIgnored let preferences: any Preferences
    let notices: NoticeCenter
    var settings: SettingsEditor
    let router: WindowRouter
    let list: FlowListViewModel
    let proxy: ProxyController
    let actions: RequestActions
    let sessionFiles: SessionFilesViewModel
    let workspaces: WorkspacesViewModel
    let breakpoints: BreakpointsViewModel
    /// Certificate trust and device setup (DeviceSetupView, the welcome sheet and the first-run list).
    let devices: DevicesViewModel
    /// Set once the first-run setup has been completed or skipped.
    var onboardingDone: Bool {
        didSet { preferences.onboardingDone = onboardingDone }
    }

    public convenience init() {
        self.init(listening: true)
    }

    /// `listening: false` leaves the model static, for previews that fill it by hand.
    convenience init(listening: Bool) {
        self.init(dependencies: listening ? .live() : .preview(), listening: listening)
    }

    init(dependencies: AppDependencies, listening: Bool = false) {
        let engine = dependencies.engine
        self.engine = engine
        clipboard = dependencies.clipboard
        preferences = dependencies.preferences
        onboardingDone = dependencies.preferences.onboardingDone
        let notices = NoticeCenter(sleep: dependencies.sleep, announce: dependencies.announce)
        self.notices = notices
        let settings = SettingsEditor(engine: engine, sleep: dependencies.sleep, notices: notices)
        self.settings = settings
        router = WindowRouter(notices: notices, focusFilterField: dependencies.focusFilterField)
        list = FlowListViewModel(store: engine.store, sleep: dependencies.sleep)
        proxy = ProxyController(runner: dependencies.runner, systemProxy: dependencies.systemProxy, notices: notices) {
            settings.value
        }
        actions = RequestActions(
            services: dependencies.requestServices,
            store: engine.store, settings: settings, notices: notices, router: router, list: list, proxy: proxy
        )
        sessionFiles = SessionFilesViewModel(
            panels: dependencies.panels, files: dependencies.files, commands: dependencies.commands,
            store: engine.store, notices: notices
        )
        workspaces = WorkspacesViewModel(engine: engine, settings: settings, notices: notices)
        breakpoints = BreakpointsViewModel(center: engine.breakpoints, settings: settings, notices: notices)
        let proxy = proxy
        devices = DevicesViewModel(probe: dependencies.devices, certificateURL: dependencies.paths.certificateURL) {
            proxy.port
        }
        connect(dependencies)
        if listening {
            observeEngine()
        }
    }

    private func connect(_ dependencies: AppDependencies) {
        list.hidesAppleTraffic = settings.hideAppleTraffic
        settings.onChange = { [list] _, new in list.hidesAppleTraffic = new.hideAppleTraffic }
        proxy.restoreLeftoverSystemProxy()
        dependencies.onTerminate { [proxy] in proxy.applicationWillTerminate() }
    }

    /// Follows the store and paused breakpoints; separate from init so tests can watch a model that has no system side effects.
    func observeEngine() {
        list.observeStore()
        breakpoints.observe()
    }

    /// The line under the window title: starting, listening (with the address), stopped, or that starting failed.
    var statusLine: String {
        proxy.status(listing: list.countText)
    }

    /// End of the welcome screen: remember the choice, then start capturing.
    func finishOnboarding() {
        onboardingDone = true
        router.sheet = nil
        if !proxy.isRunning {
            proxy.toggleRunning()
        }
    }
}
