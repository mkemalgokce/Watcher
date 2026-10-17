import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MapLocalToolTests {
    @Test(arguments: ["/static/../../etc/passwd", "/static/%2e%2e/%2e%2e/etc/passwd"])
    func directoryRefusesTraversal(path: String) {
        let escape = RequestRecord.fixture(host: "a.com", path: path)
        let directory = FileManager.default.temporaryDirectory.path
        #expect(MapLocalTool.resolve(request: escape, pattern: "a.com/static/*", directory: directory) == nil)
    }

    @Test
    func directoryServesTheFileNamedByThePath() {
        let fine = RequestRecord.fixture(host: "a.com", path: "/static/app.js?v=1")
        let directory = FileManager.default.temporaryDirectory.path
        let resolved = MapLocalTool.resolve(request: fine, pattern: "a.com/static/*", directory: directory)
        #expect(resolved?.lastPathComponent == "app.js")
    }
}
