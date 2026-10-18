import Foundation
import Testing
import WatcherTestSupport

@Suite(.tags(.integration))
struct TemporaryDirectoryTests {
    @Test
    func theSyncFolderLivesToTheEndOfTheBody() throws {
        weak var watched: TemporaryDirectory?
        var alive = false
        try withTemporaryDirectory { directory in
            watched = directory
            let derived = directory.appending("file")
            _ = derived
            alive = watched != nil
        }
        #expect(alive)
        #expect(watched == nil)
    }

    @Test
    func theAsyncFolderLivesToTheEndOfTheBodyAndIsRemovedAfterwards() async throws {
        weak var watched: TemporaryDirectory?
        var root = URL(fileURLWithPath: "/")
        var alive = false
        try await withTemporaryDirectory { directory in
            watched = directory
            root = directory.url
            let file = directory.appending("file")
            try await Task.sleep(for: .milliseconds(20))
            try Data("x".utf8).write(to: file)
            alive = watched != nil && FileManager.default.fileExists(atPath: file.path)
        }
        #expect(alive)
        #expect(watched == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
