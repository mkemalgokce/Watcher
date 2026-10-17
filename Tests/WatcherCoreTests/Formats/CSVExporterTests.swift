import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CSVExporterTests {
    @Test
    func quotesCommasAndNeutralisesSpreadsheetFormulas() throws {
        var evil = Flow.annotatedJSONPostFixture()
        evil.request.clientApp = "=HYPERLINK(\"http://x\")"
        let csv = try #require(String(bytes: CSVExporter.export([.annotatedJSONPostFixture(), evil]), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        #expect(
            lines[0]
                == "#,Method,URL,Status,Duration (ms),Request bytes,Response bytes,Content-Type,Tools,Client app"
        )
        #expect(
            lines[1] == "3,POST,\"https://api.example.com/v1/x?a=1,2\",200,250,15,2,application/json,"
                + "Map Local; Scripting,Google Chrome"
        )
        #expect(lines[2].hasSuffix("\"'=HYPERLINK(\"\"http://x\"\")\""), "\(lines[2])")
    }
}
