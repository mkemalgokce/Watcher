import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension MCPServerTests {
    @Suite(.tags(.unit))
    struct Messages {
        private let tests: MCPServerTests

        init() throws {
            tests = try MCPServerTests()
        }

        private func isError(_ reply: [String: Any]) -> Bool? {
            (reply["result"] as? [String: Any])?["isError"] as? Bool
        }

        @Test
        func pingAnswersAnEmptyResult() async throws {
            let reply = try await tests.json(tests.server.handle(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#))
            #expect(reply["id"] as? Int == 7)
            #expect((reply["result"] as? [String: Any])?.isEmpty == true)
        }

        @Test
        func aNullIdIsAnsweredWithANullId() async throws {
            let reply = try await tests.json(tests.server.handle(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))
            #expect(reply["id"] is NSNull)
            #expect(reply["result"] != nil)
        }

        @Test
        func everyToolDescribesItsStringArguments() async throws {
            let listed = try await tests.json(tests.server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
            let tools = try #require((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
            #expect(tools.count == 19)
            #expect(Set(tools.compactMap { $0["name"] as? String }).count == 19)
            for tool in tools {
                let name = tool["name"] as? String ?? "?"
                let schema = try #require(tool["inputSchema"] as? [String: Any], "\(name)")
                let properties = try #require(schema["properties"] as? [String: [String: String]], "\(name)")
                let required = try #require(schema["required"] as? [String], "\(name)")
                #expect(schema["type"] as? String == "object")
                #expect(properties.values.allSatisfy { $0["type"] == "string" && $0["description"]?.isEmpty == false })
                #expect(Set(required).isSubset(of: properties.keys), "\(name)")
                #expect((tool["description"] as? String)?.isEmpty == false)
            }
        }

        @Test(arguments: [
            (#"{"sequence":1}"#, false), (#"{"sequence":"1"}"#, false), (#"{"sequence":1.0}"#, false),
            (#"{"sequence":"abc"}"#, true), (#"{"sequence":true}"#, true), (#"{"sequence":""}"#, true),
            (#"{"sequence":null}"#, true), (#"{"sequence":[1]}"#, true), (#"{}"#, true),
        ])
        func requiredArgumentsMayBeStringsOrNumbers(arguments: String, fails: Bool) async throws {
            tests.engine.store.load([Flow.fixture(sequence: 1)])
            let reply = try await tests.callTool("get_flow_detail", arguments: arguments)
            #expect(isError(reply) == fails, "\(arguments)")
        }

        @Test
        func aNumericLimitIsHonoured() async throws {
            tests.engine.store.load((1 ... 3).map { Flow.fixture(sequence: $0) })
            let text = try await tests.text(of: tests.callTool("get_flows", arguments: #"{"limit":1}"#))
            #expect(text.components(separatedBy: "\n").count == 1)
        }

        @Test
        func aMissingRequiredArgumentIsNamed() async throws {
            let reply = try await tests.callTool("create_reverse_proxy", arguments: #"{"local_port":8080}"#)
            #expect(isError(reply) == true)
            #expect(tests.text(of: reply) == "Missing required argument: remote_host")
        }
    }
}
