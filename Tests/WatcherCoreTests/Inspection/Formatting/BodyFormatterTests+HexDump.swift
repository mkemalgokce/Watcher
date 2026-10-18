import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension BodyFormatterTests {
    struct HexDump {
        @Test
        func rowsShowOffsetHexAndPrintableText() {
            let data = Data("ABCDEFGHIJKLMNOP\u{0}~".utf8)
            #expect(BodyFormatter.hexDump(data) == """
            00000000  41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f 50  ABCDEFGHIJKLMNOP
            00000010  00 7e                                            .~
            """)
        }

        @Test
        func emptyDataGivesNoRows() {
            #expect(BodyFormatter.hexDump(Data()).isEmpty)
        }

        @Test
        func bytesBeyondTheLimitAreCounted() {
            #expect(BodyFormatter.hexDump(Data(repeating: 0xFF, count: 20), limit: 16) == """
            00000000  ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff  ................
            … 4 more bytes
            """)
        }
    }
}
