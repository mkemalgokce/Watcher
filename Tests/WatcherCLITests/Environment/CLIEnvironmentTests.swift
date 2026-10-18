import Foundation
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct CLIEnvironmentTests {
    @Test(arguments: [
        ("~", "/Users/me"), ("~/x.har", "/Users/me/x.har"), ("/tmp/s.har", "/tmp/s.har"),
        ("~/a/b.csv", "/Users/me/a/b.csv"),
    ])
    func aTildeInATypedPathMeansTheHomeFolder(typed: String, path: String) {
        #expect(CLIHarness().environment.url(forPath: typed).path == path)
    }

    @Test
    func aRelativePathIsResolvedAgainstTheWorkingDirectory() {
        let url = CLIHarness().environment.url(forPath: "s.har")
        #expect(url.path == URL(fileURLWithPath: "s.har").path)
    }

    @Test(arguments: [(["WATCHER_HOME": "/tmp/isolated"], "/tmp/isolated"), ([:], "/Users/me/.watcher")])
    func supportFilesLiveWhereWatcherHomeSays(variables: [String: String], directory: String) {
        var environment = CLIHarness().environment
        environment.variables = variables
        #expect(environment.supportDirectory.path == directory)
    }
}
