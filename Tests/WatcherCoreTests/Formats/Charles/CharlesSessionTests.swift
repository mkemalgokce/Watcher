import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CharlesSessionTests {
    @Test
    func importsCharlesJSONAndRejectsGarbage() throws {
        let json = """
        [{"scheme":"https","host":"api.example.com","port":443,"method":"POST","path":"/v1/login","query":"a=1",
          "request":{"header":{"headers":[{"name":"Content-Type","value":"application/json"}]},
                     "body":{"text":"{\\"u\\":1}"}},
          "response":{"status":200,"header":{"headers":[]},"body":{"encoded":"aGk="}},
          "times":{"start":"2026-10-16T10:00:00.000Z"},"durations":{"total":120}}]
        """
        let flow = try #require(CharlesSession.flows(from: Data(json.utf8)).first)
        #expect(flow.request.url == "https://api.example.com/v1/login?a=1")
        #expect(flow.request.body == Data(#"{"u":1}"#.utf8))
        #expect(flow.response?.body == Data("hi".utf8))
        #expect(abs((flow.duration ?? 0) - 0.12) <= 0.001)
        #expect(throws: (any Error).self) { try CharlesSession.flows(from: Data("not json".utf8)) }
    }
}
