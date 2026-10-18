import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .serialized)
struct JSONFormatterTests {
    @Test
    func prettyKeepsOrderStringsAndEmptyContainers() {
        let out = JSONFormatter.pretty(#"{"b":[1,2],"a":{"x":"p,q:{r}"},"e":{},"l":[]}"#)
        #expect(out == """
        {
          "b": [
            1,
            2
          ],
          "a": {
            "x": "p,q:{r}"
          },
          "e": {},
          "l": []
        }
        """)
    }

    @Test
    func minifyRoundTrips() {
        let source = #"{"a": [1, 2], "s": "x y"}"#
        #expect(JSONFormatter.minify(JSONFormatter.pretty(source)) == #"{"a":[1,2],"s":"x y"}"#)
        #expect(JSONFormatter.pretty("not json") == "not json")
    }

    @Test
    func sortedKeysPutsKeysInOrder() throws {
        let sorted = try #require(JSONFormatter.sortedKeys(Data(#"{"b":1,"a":2}"#.utf8)))
        #expect(try #require(sorted.range(of: "\"a\"")).lowerBound < #require(sorted.range(of: "\"b\"")).lowerBound)
    }

    @Test(.tags(.timing))
    func prettyPrintsMegabytesQuickly() {
        let item = #"{"id":12345,"name":"Ada \"Lovelace\"","tags":["a","b",null,true],"#
            + #""empty":{},"list":[],"score":-1.5e3},"#
        let text = "[" + String(repeating: item, count: 60000) + #"{"end":1}]"# // ~6 MB
        var pretty = Data()
        let elapsed = cpuTime { pretty = JSONFormatter.prettyData(Data(text.utf8)) }
        #expect(elapsed < .seconds(30))
        #expect(pretty.count > text.utf8.count)
        #expect(
            String(bytes: JSONFormatter.minifyData(pretty), encoding: .utf8) == text,
            "same document after minifying again: nothing was lost or reordered"
        )
    }
}
