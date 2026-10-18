import Foundation
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct LiveShutdownSignalTests {
    @Test
    func aCaughtSignalAsksToStopInsteadOfEndingTheProcess() async {
        let caught = LockedBox(false)
        let requests = LiveShutdownSignal.stopRequest(on: [SIGUSR1])()
        let listening = Task {
            for await _ in requests {
                caught.mutate { $0 = true }
                break
            }
        }
        // The source registers asynchronously, so a signal raised before that is missed; keep raising until one lands.
        let stopped = await eventually(timeout: 30) {
            raise(SIGUSR1)
            return caught.value
        }
        listening.cancel()
        #expect(stopped)
    }
}
