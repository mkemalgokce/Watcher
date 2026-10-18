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
        commands: CommandRunnerSpy? = nil
    ) throws -> AppDependencies {
        let files = files ?? FileAccessFake()
        return try AppDependencies(
            engine: engine ?? .inMemory(files: files),
            clipboard: clipboard ?? ClipboardSpy(),
            sleep: sleep ?? liveSleep,
            announce: (announcer ?? AnnouncerSpy()).announce,
            panels: panels ?? FilePanelsStub(),
            files: files.access,
            commands: (commands ?? CommandRunnerSpy()).runner
        )
    }
}

public extension AppModel {
    /// A model on `AppDependencies.test`, with the doubles passed in for the test to inspect.
    @MainActor
    static func test(clipboard: ClipboardSpy? = nil) throws -> AppModel {
        try AppModel(dependencies: .test(clipboard: clipboard))
    }
}
