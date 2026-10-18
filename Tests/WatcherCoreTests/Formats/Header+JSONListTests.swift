import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HeaderJSONListTests {
    @Test(arguments: [
        (
            [["name": "A", "value": "1"], "junk", ["name": "B", "value": "2"]] as [Any],
            [Header("A", "1"), Header("B", "2")]
        ),
        ([["name": "A"], ["value": "1"], 7] as [Any], []),
        ([] as [Any], []),
    ])
    func entriesThatAreNotHeadersAreSkippedOneByOne(list: [Any], headers: [Header]) {
        #expect([Header](jsonList: list) == headers)
    }

    @Test
    func aValueThatIsNotAListGivesNoHeaders() {
        #expect([Header](jsonList: "A: 1").isEmpty)
        #expect([Header](jsonList: nil).isEmpty)
    }
}
