import Foundation
import WatcherCore
@testable import WatcherUI

public extension AppDependencies {
    /// Everything in memory: an engine on a fake file system and doubles for every system service. Delays such as the
    /// notice timeout and the settings debounce never end unless a test passes `sleep: liveSleep` or a `SleepGate`.
    @MainActor
    static func test(
        engine: WatcherEngine? = nil,
        clipboard: ClipboardSpy? = nil,
        sleep: Sleep? = nil,
        announcer: AnnouncerSpy? = nil,
        panels: FilePanelsStub? = nil,
        files: FileAccessFake? = nil,
        commands: CommandRunnerSpy? = nil,
        preferences: PreferencesFake? = nil,
        runner: (any ProxyRunning)? = nil,
        systemProxy: (any SystemProxying)? = nil,
        lifecycle: AppLifecycleSpy? = nil,
        sender: (any RequestSending)? = nil,
        previews: (@Sendable (Flow) async -> [PreviewOutput])? = nil,
        workspace: WorkspaceOpenerSpy? = nil,
        loginItem: LoginItemStub? = nil,
        clock: ClockStub? = nil,
        devices: DevicesViewModel.DeviceProbe = .none
    ) throws -> AppDependencies {
        let files = files ?? FileAccessFake()
        let engine = try engine ?? .inMemory(files: files)
        return AppDependencies(
            engine: engine,
            clipboard: clipboard ?? ClipboardSpy(),
            sleep: sleep ?? sleepUntilCancelled,
            announce: (announcer ?? AnnouncerSpy()).announce,
            panels: panels ?? FilePanelsStub(),
            files: files.access,
            commands: (commands ?? CommandRunnerSpy()).runner,
            preferences: preferences ?? PreferencesFake(),
            runner: runner ?? ProxyRunnerStub(),
            systemProxy: systemProxy ?? SystemProxySpy(),
            onTerminate: (lifecycle ?? AppLifecycleSpy()).onTerminate,
            sender: sender ?? RequestSenderSpy(),
            previews: previews ?? { [engine] in await engine.previews(for: $0) },
            workspace: workspace ?? WorkspaceOpenerSpy(),
            paths: SupportPaths(directory: URL(fileURLWithPath: "/fake-home/.watcher")),
            focusFilterField: {},
            devices: devices,
            loginItem: (loginItem ?? LoginItemStub()).loginItem,
            now: (clock ?? ClockStub()).now,
            homeDirectory: URL(fileURLWithPath: "/fake-home"),
            appInfo: AppInfo(
                bundleIdentifier: nil, shortVersion: nil, buildNumber: nil,
                operatingSystem: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                architecture: "arm64", homeDirectory: "/fake-home"
            ),
            faviconDownload: { _ in nil }
        )
    }
}

public extension AppModel {
    /// A model on `AppDependencies.test`, with the doubles passed in for the test to inspect.
    @MainActor
    static func test(clipboard: ClipboardSpy? = nil, sleep: Sleep? = nil, clock: ClockStub? = nil) throws -> AppModel {
        try AppModel(dependencies: .test(clipboard: clipboard, sleep: sleep, clock: clock))
    }

    /// A test model showing the preview's demo requests, the first one selected.
    @MainActor
    static func demo() throws -> AppModel {
        try test().showingDemoData()
    }
}
