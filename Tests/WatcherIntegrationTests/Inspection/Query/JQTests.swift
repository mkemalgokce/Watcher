import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .externalTool))
struct JQTests {
    @Test(.enabled(if: ExternalTool.jq.isAvailable, "needs jq"))
    func runsRealFiltersAndRefusesOptionInjection() {
        let json = Data(#"{"users":[{"id":1,"name":"Ada"},{"id":2,"name":"Linus"}]}"#.utf8)
        let names = JQ.run(".users[] | .name", on: json)?.split(separator: "\n").map(String.init)
        #expect(names == ["\"Ada\"", "\"Linus\""])
        #expect(JQ.run("[.users[].id] | add", on: json)?.trimmingCharacters(in: .whitespacesAndNewlines) == "3")
        #expect(JQ.run(".users[", on: json) == nil, "invalid program")
        #expect(JQ.run("--help", on: json) == nil, "must not be read as an option")
        #expect(
            JQ.run("$ENV | length", on: json)?.trimmingCharacters(in: .whitespacesAndNewlines) == "0",
            "environment is not exposed"
        )
        #expect(
            JQ.looksLikeJQ(".a") && JQ.looksLikeJQ("map(.x)") && !JQ.looksLikeJQ("users[0].name")
                && !JQ.looksLikeJQ("email")
        )
    }
}
