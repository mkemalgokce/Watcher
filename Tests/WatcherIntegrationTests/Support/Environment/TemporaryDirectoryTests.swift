import Foundation
import Testing
import WatcherTestSupport

@Suite(.tags(.integration))
struct TemporaryDirectoryTests {
    @Test
    func theFolderLivesToTheEndOfTheBodyEvenWhenOnlyADerivedURLIsUsed() async throws {
        var root = URL(fileURLWithPath: "/")
        let derived = try await withTemporaryDirectory { directory -> URL in
            root = directory.url
            return directory.appending("file")
        }
        _ = derived
        #expect(!FileManager.default.fileExists(atPath: root.path))

        try await withTemporaryDirectory { directory in
            let file = directory.appending("file")
            try await Task.sleep(for: .milliseconds(20))
            try Data("x".utf8).write(to: file)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }
}
