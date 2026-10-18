import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MapRemoteRuleTests {
    private let rule = MapRemoteRule(matching: MatchingRule(pattern: "*"), destination: .init(host: "h"))

    @Test
    func onlyTheMatchingAndDestinationAreRequired() throws {
        #expect(try decode(rule, dropping: ["name", "isEnabled", "preserveHostHeader", "folder"]) == rule)
    }

    @Test
    func everyFieldSurvivesARoundTrip() throws {
        var rule = MapRemoteRule(
            name: "n",
            isEnabled: false,
            matching: MatchingRule(pattern: "a"),
            destination: .init(scheme: "https", port: 1),
            preserveHostHeader: true
        )
        rule.folder = "f"
        #expect(try JSONDecoder().decode(MapRemoteRule.self, from: JSONEncoder().encode(rule)) == rule)
    }

    @Test(arguments: ["matching", "destination"])
    func aMissingRequiredKeyIsRejected(key: String) {
        #expect(throws: DecodingError.self) { try decode(rule, dropping: [key]) }
    }

    private func decode(_ rule: MapRemoteRule, dropping keys: [String]) throws -> MapRemoteRule {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
        keys.forEach { object.removeValue(forKey: $0) }
        return try JSONDecoder().decode(MapRemoteRule.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
