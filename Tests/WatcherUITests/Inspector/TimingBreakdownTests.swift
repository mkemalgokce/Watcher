import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// How long a request waited for the server and how long it took to download, as the Timing tab shows it.
struct TimingBreakdownTests {
    @Test
    func timingSplitsWaitingAndDownload() {
        let timing = TimingBreakdown(.fixture(duration: 2, timeToFirstByte: 0.5))
        #expect(timing.isComplete)
        #expect(timing.phases.map(\.seconds) == [0.5, 1.5])
        #expect(timing.phases.map(\.fraction) == [0.25, 0.75])
        #expect(timing.verdict.contains("downloading"))
    }

    @Test
    func timingEdgeCases() {
        // No first-byte time: everything counts as waiting.
        #expect(TimingBreakdown(.fixture(duration: 1)).phases.map(\.fraction) == [1, 0])
        #expect(TimingBreakdown(.fixture(duration: 1)).verdict.contains("server"))
        // A first byte after the end (clock skew) never yields a negative phase.
        #expect(TimingBreakdown(.fixture(duration: 1, timeToFirstByte: 3)).phases.map(\.seconds) == [1, 0])
        // Not finished, or zero length.
        let pending = TimingBreakdown(.fixture(state: .pending))
        #expect(!pending.isComplete)
        #expect(pending.phases.map(\.fraction) == [0, 0])
        #expect(pending.verdict == "The response has not finished yet.")
        #expect(TimingBreakdown(.fixture(duration: 0.05)).verdict.hasPrefix("Fast"))
    }
}
