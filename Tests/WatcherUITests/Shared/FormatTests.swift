import Testing
import WatcherTestSupport
@testable import WatcherUI

/// Sizes and durations as the list and inspector print them.
@Suite(.tags(.unit))
struct FormatTests {
    @Test
    func bytesReadExactlyForSmallAndEmptyBodies() {
        #expect(Format.bytes(0) == "0 B", "an empty body reads as empty, not \"Zero KB\"")
        #expect(Format.bytes(69) == "69 B")
        #expect(Format.bytes(999) == "999 B")
        #expect(Format.bytes(1000) != "1000 B")
    }

    @Test
    func durationsReadInMillisecondsBelowASecondAndSecondsAbove() {
        #expect(Format.duration(0.184) == "184 ms")
        #expect(Format.duration(0) == "0 ms")
        #expect(Format.duration(5) == "5.00 s")
    }
}
