import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    @Suite(.timeLimit(.minutes(1)))
    struct Timing {
        private static let answers: [RequestDecision] = [
            .respond(ResponseRecord(status: 200, headers: [], body: Data())), .block(hidden: false),
        ]

        /// A server whose clock moves 1.5 s on every reading.
        private func server(answering decision: RequestDecision) -> ProxyServer {
            let ticks = LockedBox(0.0)
            let server = ProxyServer(authority: nil, now: {
                ticks.mutate { $0 += 1.5 }
                return Date(timeIntervalSince1970: ticks.value)
            })
            server.tools.set([ToolStub(decision: decision)])
            return server
        }

        @Test(arguments: answers)
        func aFlowAnsweredByAToolLastsAsLongAsTheClockSays(decision: RequestDecision) async throws {
            let server = server(answering: decision)
            _ = await server.process(.fixture())
            #expect(server.store.all.first?.duration == 1.5)
            try await server.stop()
        }

        @Test(arguments: [101, 502])
        func aTunnelledUpgradeLastsUntilTheOriginAnswers(status: Int) async throws {
            let store = FlowStore(now: { Date(timeIntervalSince1970: 100) })
            let server = ProxyServer(store: store, authority: nil, now: { Date(timeIntervalSince1970: 101.5) })
            guard case let .tunnel(_, id) = await server.prepareUpgrade(.fixture()) else {
                throw TestSupportError("the upgrade was answered by a tool")
            }
            server.finishUpgrade(id, status: status)
            #expect(store.all.first?.duration == 1.5)
            try await server.stop()
        }

        @Test(arguments: answers)
        func anUpgradeAnsweredByAToolLastsAsLongAsTheClockSays(decision: RequestDecision) async throws {
            let server = server(answering: decision)
            _ = await server.prepareUpgrade(.fixture())
            #expect(server.store.all.first?.duration == 1.5)
            try await server.stop()
        }
    }
}
