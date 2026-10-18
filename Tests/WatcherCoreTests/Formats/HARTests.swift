import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HARTests {
    @Test
    func exportThenImportKeepsURLBodyStatusAndDuration() throws {
        let imported = try HAR.flows(from: HAR.export([Flow.jsonPostFixture()]))
        let flow = try #require(imported.first)
        #expect(flow.request.url == "https://api.example.com/v1/users?id=7")
        #expect(flow.request.body == Data(#"{"name":"it's"}"#.utf8))
        #expect(flow.response?.status == 201)
        #expect(abs((flow.duration ?? 0) - 0.25) <= 0.001)
    }

    @Test(arguments: [nil, "yesterday"] as [String?])
    func aMissingOrUnreadableStartTimeIsTheImportTime(start: String?) throws {
        let importTime = Date(timeIntervalSinceReferenceDate: 5)
        var entry: [String: Any] = ["request": ["method": "GET", "url": "http://h/"]]
        entry["startedDateTime"] = start
        let data = try JSONSerialization.data(withJSONObject: ["log": ["entries": [entry]]])
        #expect(try HAR.flows(from: data, now: importTime).first?.startedAt == importTime)
    }

    @Test
    func headersWithoutANameOrValueAreSkipped() throws {
        let headers = [["name": "A", "value": "1"], ["name": "B"], ["value": "2"]]
        let entry: [String: Any] = ["request": ["method": "GET", "url": "http://h/", "headers": headers]]
        let data = try JSONSerialization.data(withJSONObject: ["log": ["entries": [entry]]])
        #expect(try HAR.flows(from: data).first?.request.headers == [Header("A", "1")])
    }

    @Test(arguments: [(nil, 2000.0, 0.0), (0.5, 500, 1500)] as [(TimeInterval?, Double, Double)])
    func timingsAddUpToTheEntryTime(timeToFirstByte: TimeInterval?, wait: Double, receive: Double) throws {
        let data = try HAR.export([Flow.fixture(duration: 2, timeToFirstByte: timeToFirstByte)])
        let log = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])["log"] as? [String: Any]
        let entry = try #require((log?["entries"] as? [[String: Any]])?.first)
        let timings = try #require(entry["timings"] as? [String: Double])
        #expect(timings["wait"] == wait)
        #expect(timings["receive"] == receive)
    }

    @Test
    func aRequestBodyThatIsNotUTF8SurvivesARoundTrip() throws {
        let body = Data([0xFF, 0x00, 0x80])
        let flow = Flow.fixture(request: .fixture(method: "POST", body: body))
        #expect(try HAR.flows(from: HAR.export([flow])).first?.request.body == body)
    }
}
