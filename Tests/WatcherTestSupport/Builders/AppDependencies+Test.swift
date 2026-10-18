import Foundation
import WatcherCore
@testable import WatcherUI

public extension AppDependencies {
    /// Everything in memory: an engine on a fake file system and doubles for every system service.
    @MainActor
    static func test(engine: WatcherEngine? = nil, clipboard: ClipboardSpy? = nil) throws -> AppDependencies {
        try AppDependencies(engine: engine ?? .inMemory(), clipboard: clipboard ?? ClipboardSpy())
    }
}

public extension AppModel {
    /// A model on `AppDependencies.test`, with the doubles passed in for the test to inspect.
    @MainActor
    static func test(clipboard: ClipboardSpy? = nil) throws -> AppModel {
        try AppModel(dependencies: .test(clipboard: clipboard))
    }
}
