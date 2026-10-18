import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Opening the engine at launch, and what happens when the data folder cannot be read.
@MainActor
@Suite(.tags(.unit))
struct OpenEngineTests {
    private struct Unreadable: Error, CustomStringConvertible {
        let description = "settings.json is unreadable"
    }

    private let directory = URL(fileURLWithPath: "/home/.watcher")
    private let fallback = URL(fileURLWithPath: "/tmp/watcher-fallback")

    @Test
    func anEngineThatOpensIsUsedWithoutAProblem() {
        let opened = LockedBox<[URL]>([])
        let result = AppDependencies.openEngine(in: directory, fallback: fallback) { url in
            opened.mutate { $0.append(url) }
            return try .inMemory()
        }
        #expect(opened.value == [directory])
        #expect(result.directory == directory)
        #expect(result.problem == nil)
    }

    @Test
    func anEngineThatCannotOpenFallsBackToTheTemporaryFolderAndSaysWhy() {
        let opened = LockedBox<[URL]>([])
        let result = AppDependencies.openEngine(in: directory, fallback: fallback) { url in
            opened.mutate { $0.append(url) }
            if url == directory {
                throw Unreadable()
            }
            return try .inMemory()
        }
        #expect(opened.value == [directory, fallback])
        #expect(result.directory == fallback, "certificate paths must follow the folder the engine signs in")
        #expect(result.problem?.folder == directory)
        #expect(result.problem?.message == "Cannot open Watcher's data in /home/.watcher: settings.json is unreadable. "
            + "This session records into a temporary folder; fix the folder and relaunch Watcher.")
    }
}
