import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct SimulatorCertCommandTests {
    @Test(arguments: [([], "booted"), (["--device", "all"], "all"), (["--device", "ABC-123"], "ABC-123")])
    func deviceDefaultsToTheBootedSimulator(arguments: [String], device: String) throws {
        #expect(try SimulatorCert.parse(arguments).device == device)
    }
}
