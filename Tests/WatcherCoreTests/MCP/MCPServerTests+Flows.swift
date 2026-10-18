import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension MCPServerTests {
    @Suite(.tags(.unit))
    struct Flows {
        private let tests: MCPServerTests

        init() throws {
            tests = try MCPServerTests()
        }

        private func load(_ count: Int) {
            let flows = (1 ... count).map { sequence in
                Flow.fixture(
                    sequence: sequence,
                    request: .fixture(host: "h\(sequence).test", path: "/p"),
                    response: .fixture(status: 200)
                )
            }
            tests.engine.store.load(flows)
        }

        private func rows(_ arguments: String) async throws -> [String] {
            let text = try await tests.text(of: tests.callTool("get_flows", arguments: arguments))
            return text.isEmpty ? [] : text.components(separatedBy: "\n")
        }

        @Test(arguments: [
            (#"{"limit":"-1"}"#, 0), (#"{"limit":"0"}"#, 0), (#"{"limit":"abc"}"#, 3), (#"{}"#, 3),
        ])
        func anUnusableLimitNeverCrashes(arguments: String, expected: Int) async throws {
            load(3)
            #expect(try await rows(arguments).count == expected)
        }

        @Test
        func aLimitKeepsTheNewestFlowsNewestLast() async throws {
            load(3)
            let shown = try await rows(#"{"limit":"2"}"#)
            #expect(shown.map { $0.split(separator: "\t")[0] } == ["2", "3"])
        }

        @Test
        func theFilterMatchesUrlsIgnoringCase() async throws {
            load(3)
            #expect(try await rows(#"{"filter":"H2.TEST"}"#).count == 1)
            #expect(try await rows(#"{"filter":"nothing"}"#).isEmpty)
        }

        @Test
        func aRowIsSequenceStatusMethodAndUrlWithADashWhilePending() async throws {
            let posted = RequestRecord.fixture(method: "POST", host: "a.test", path: "/x")
            let waiting = RequestRecord.fixture(host: "a.test", path: "/y")
            tests.engine.store.load([
                Flow.fixture(sequence: 1, request: posted, response: .fixture(status: 201)),
                Flow.fixture(sequence: 2, request: waiting, response: nil, state: .pending),
            ])
            let expected = ["1\t201\tPOST\thttps://a.test/x", "2\t-\tGET\thttps://a.test/y"]
            #expect(try await rows("{}") == expected)
        }
    }
}
