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
    let clipboard: any Clipboard
    let preferences: any Preferences
    let notices: NoticeCenter
    var settings: SettingsEditor
    let router: WindowRouter
    let list: FlowListViewModel
    let proxy: ProxyController
    let actions: RequestActions
    let externalApps: ExternalApps
    let sessionFiles: SessionFilesViewModel
    let workspaces: WorkspacesViewModel
    let breakpoints: BreakpointsViewModel
    /// Certificate trust and device setup (DeviceSetupView, the welcome sheet and the first-run list).
    let devices: DevicesViewModel
    let viewer: ViewerOptions
    let filePicker: FilePicker
    let settingsPane: SettingsViewModel
    let icons: IconStore
    /// The time the inspector and Compose measure against.
    let now: @Sendable () -> Date
    private let sleep: Sleep
    let appInfo: AppInfo
    let supportDirectory: URL
    /// Set when the engine could not open the user's data folder; the window shows it until the app is relaunched.
    let startupProblem: StartupProblem?
    private let files: FileAccess
    private let homeDirectory: URL
    /// Set once the first-run setup has been completed or skipped.
    var onboardingDone: Bool {
        didSet { preferences.onboardingDone = onboardingDone }
    }

    /// The app's model: the real services, following the engine from the start.
    public convenience init() {
        self.init(dependencies: .live())
        observeEngine()
    }

    /// A model that stays as it is until `observeEngine()`, so previews and tests can fill it by hand.
    init(dependencies: AppDependencies) {
        let engine = dependencies.engine
        self.engine = engine
        clipboard = dependencies.clipboard
        now = dependencies.now
        sleep = dependencies.sleep; files = dependencies.files; homeDirectory = dependencies.homeDirectory
        appInfo = dependencies.appInfo; supportDirectory = dependencies.paths.directory
        preferences = dependencies.preferences; startupProblem = dependencies.startupProblem
        onboardingDone = dependencies.preferences.onboardingDone
        viewer = ViewerOptions(preferences: dependencies.preferences)
        filePicker = FilePicker(panels: dependencies.panels, files: dependencies.files)
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
        externalApps = ExternalApps(workspace: dependencies.workspace, notices: notices)
        sessionFiles = SessionFilesViewModel(
            panels: dependencies.panels, files: dependencies.files, commands: dependencies.commands,
            store: engine.store, notices: notices
        )
        workspaces = WorkspacesViewModel(engine: engine, settings: settings, notices: notices)
        breakpoints = BreakpointsViewModel(center: engine.breakpoints, settings: settings, notices: notices)
        settingsPane = SettingsViewModel(
            proxy: proxy, settings: settings, preferences: dependencies.preferences,
            loginItem: dependencies.loginItem, notices: notices
        )
        let proxy = proxy
        devices = DevicesViewModel(probe: dependencies.devices, certificateURL: dependencies.paths.certificateURL) {
            proxy.port
        }
        icons = IconStore(dependencies)
        connect(dependencies)
    }

    private func connect(_ dependencies: AppDependencies) {
        list.hidesAppleTraffic = settings.hideAppleTraffic
        settings.onChange = { [list] _, new in list.hidesAppleTraffic = new.hideAppleTraffic }
        proxy.restoreLeftoverSystemProxy()
        dependencies.onTerminate { [proxy] in proxy.applicationWillTerminate() }
    }

    func showStartupFolder() {
        guard let startupProblem else { return }
        externalApps.reveal(startupProblem.folder)
    }

    /// Follows the store and paused breakpoints; separate from init so tests can watch a model that has no system side effects.
    func observeEngine() {
        list.observeStore()
        breakpoints.observe()
    }

    /// The body viewer's model for one side of an exchange, with this window's protobuf schemas and clock.
    func bodyViewerModel(flow: Flow, side: MessageSide) -> BodyViewerViewModel {
        BodyViewerViewModel(
            flow: flow, side: side, mode: viewer.mode, sortKeys: viewer.sortsKeys,
            protobufText: { [engine] flow, side in engine.bodyText(of: flow, response: side == .response) },
            sleep: sleep
        )
    }

    /// The Tools window's model, checking certificate files on this window's file system and home folder.
    func toolsViewModel() -> ToolsViewModel {
        ToolsViewModel(settings: settings, router: router, proxy: proxy, files: files, homeDirectory: homeDirectory)
    }

    /// The request actions for `flow`, applying to `ids` when given (a multi-selection) and otherwise to `flow` alone.
    func requestCommands(for flow: Flow?, ids: Set<Flow.ID>? = nil) -> RequestCommands {
        RequestCommands(flow: flow, ids: ids, actions: actions, router: router, sessionFiles: sessionFiles)
    }

    var statusBar: StatusBarViewModel {
        StatusBarViewModel(
            proxy: proxy, settings: settings, devices: devices, breakpoints: breakpoints, list: list,
            sessionFiles: sessionFiles, notices: notices, actions: actions, router: router
        ) { [self] in statusLine }
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
