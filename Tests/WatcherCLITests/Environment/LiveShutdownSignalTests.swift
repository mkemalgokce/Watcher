import Foundation
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct LiveShutdownSignalTests {
    @Test
    func aCaughtSignalAsksToStopInsteadOfEndingTheProcess() async {
        // The handler is process-wide; put back the one the rest of this test process runs with.
        let previousHandler = signal(SIGUSR1, SIG_DFL)
        defer { signal(SIGUSR1, previousHandler) }
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
