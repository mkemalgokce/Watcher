import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HeaderTests {
    @Test(arguments: [
        ("A: 1", Header("A", "1")), ("A:1", Header("A", "1")), ("  A :  1  ", Header("A", "1")),
        ("A: b: c", Header("A", "b: c")), ("A:", Header("A", "")), (": v", Header("", "v")),
    ])
    func aLineSplitsAtTheFirstColon(line: String, header: Header) {
        #expect(Header(line: line) == header)
    }

    @Test(arguments: ["", "no colon", "   "])
    func aLineWithoutAColonIsNotAHeader(line: String) {
        #expect(Header(line: line) == nil)
    }
}
