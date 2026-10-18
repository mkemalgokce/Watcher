import Foundation
import Testing
@testable import WatcherCore

extension CharlesSessionTests {
    struct Transactions {
        private let importTime = Date(timeIntervalSinceReferenceDate: 5)

        private func flow(_ transaction: String) throws -> Flow {
            let data = Data("[{\"host\":\"h\",\"method\":\"GET\",\(transaction)}]".utf8)
            return try #require(CharlesSession.flows(from: data, now: importTime).first)
        }

        @Test(arguments: [
            (#""scheme":"https","actualPort":-1"#, 443),
            (#""scheme":"http","actualPort":-1,"port":8080"#, 8080),
            (#""scheme":"http","actualPort":81,"port":8080"#, 81),
            (#""actualPort":-1"#, 80),
        ])
        func onlyAPositivePortCountsOtherwiseTheSchemeDefault(fields: String, port: Int) throws {
            #expect(try flow(fields).request.port == port)
        }

        @Test
        func aTransactionWithoutAResponseFailed() throws {
            let flow = try flow(#""path":"/""#)
            #expect(flow.state == .failed)
            #expect(flow.response == nil)
        }

        @Test
        func aBodyThatIsNotBase64FallsBackToItsText() throws {
            let flow = try flow(#""request":{"body":{"encoded":"%%%","text":"plain"}}"#)
            #expect(flow.request.body == Data("plain".utf8))
        }

        @Test(arguments: [#""path":"/""#, #""times":{"start":"yesterday"}"#])
        func aMissingOrUnreadableStartTimeIsTheImportTime(fields: String) throws {
            #expect(try flow(fields).startedAt == importTime)
        }

        @Test
        func headersWithoutANameOrValueAreSkipped() throws {
            let headers = #"{"header":{"headers":[{"name":"A","value":"1"},{"name":"B"},{"value":"2"}]}}"#
            #expect(try flow(#""request":\#(headers)"#).request.headers == [Header("A", "1")])
        }
    }
}
