import Foundation
import WatcherCore
@testable import WatcherUI

public extension AppDependencies {
    /// Everything in memory: an engine on a fake file system and doubles for every system service.
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
        workspace: WorkspaceOpenerSpy? = nil,
        loginItem: LoginItemStub? = nil
    ) throws -> AppDependencies {
        let files = files ?? FileAccessFake()
        let engine = try engine ?? .inMemory(files: files)
        return AppDependencies(
            engine: engine,
            clipboard: clipboard ?? ClipboardSpy(),
            sleep: sleep ?? liveSleep,
            announce: (announcer ?? AnnouncerSpy()).announce,
            panels: panels ?? FilePanelsStub(),
            files: files.access,
            commands: (commands ?? CommandRunnerSpy()).runner,
            preferences: preferences ?? PreferencesFake(),
            runner: runner ?? ProxyRunnerStub(),
            systemProxy: systemProxy ?? SystemProxySpy(),
            onTerminate: (lifecycle ?? AppLifecycleSpy()).onTerminate,
            sender: sender ?? RequestSenderSpy(),
            workspace: workspace ?? WorkspaceOpenerSpy(),
            paths: SupportPaths(directory: URL(fileURLWithPath: "/fake-home/.watcher")),
            focusFilterField: {},
            devices: .none,
            loginItem: (loginItem ?? LoginItemStub()).loginItem
        )
    }
}

public extension AppModel {
    /// A model on `AppDependencies.test`, with the doubles passed in for the test to inspect.
    @MainActor
    static func test(clipboard: ClipboardSpy? = nil) throws -> AppModel {
        try AppModel(dependencies: .test(clipboard: clipboard))
    }

    /// A test model showing the preview's demo requests, the first one selected.
    @MainActor
    static func demo() throws -> AppModel {
        try test().showingDemoData()
    }
}
