import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension FlowTests {
    struct Coding {
        private var everyField: Flow {
            var flow = Flow.fixture(duration: 1.5, timeToFirstByte: 0.5)
            flow.error = "e"; flow.appliedTools = ["Map Local"]; flow.upstreamHTTPVersion = "HTTP/2"
            flow.clientTLS = "TLS 1.3 · h2"; flow.isStarred = true; flow.comment = "c"
            let date = Date(timeIntervalSinceReferenceDate: 1)
            let message = WebSocketMessage(
                direction: .serverToClient, kind: .binary, payload: Data([1]), date: date, isCompressed: true
            )
            flow.webSocketMessages = [message]
            return flow
        }

        private func json(_ flow: Flow) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try encoder.encode(flow)
        }

        @Test
        func everyFieldSurvivesARoundTrip() throws {
            let encoded = try json(everyField)
            #expect(try json(JSONDecoder().decode(Flow.self, from: encoded)) == encoded)
        }

        @Test(arguments: ["id", "sequence", "startedAt", "request", "state", "appliedTools"])
        func aMissingRequiredKeyIsRejected(key: String) throws {
            var object = try #require(JSONSerialization.jsonObject(with: json(everyField)) as? [String: Any])
            object.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(Flow.self, from: data) }
        }
    }
}
