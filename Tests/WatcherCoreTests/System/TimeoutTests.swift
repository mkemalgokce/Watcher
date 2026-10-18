import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct TimeoutTests {
    @Test
    func workThatOutlastsTheLimitIsCancelledAndReportedAsTimedOut() async {
        let spy = SleepSpy()
        let error = await #expect(throws: TimedOut.self) {
            try await withTimeout(.seconds(7), "the thing", sleep: spy.sleep) {
                try await sleepUntilCancelled(.zero)
            }
        }
        #expect(error?.description.contains("the thing did not answer within") == true)
        #expect(spy.durations == [.seconds(7)])
    }

    @Test
    func workThatFinishesFirstReturnsItsValueWhileTheClockIsStillWaiting() async throws {
        let value = try await withTimeout(.seconds(7), "the thing", sleep: sleepUntilCancelled) { 42 }
        #expect(value == 42)
    }
}
