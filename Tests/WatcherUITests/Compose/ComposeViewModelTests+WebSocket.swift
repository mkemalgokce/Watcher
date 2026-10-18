import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ComposeViewModelTests {
    /// A ws:// or wss:// address opens a WebSocket session instead of sending an HTTP request.
    @MainActor
    struct WebSocket {
        @Test(arguments: ["ws://echo.test/socket", "wss://echo.test/socket"])
        func aWebSocketAddressGivesASessionWithTheEnabledHeadersAndLines(address: String) throws {
            let viewModel = ComposeViewModel()
            viewModel.address = address
            viewModel.headers = [KeyValue("Origin", "https://a.test"), KeyValue("X-Off", "1")]
            viewModel.headers[1].isEnabled = false
            viewModel.bodyText = "hello\n\nworld"
            let session = try #require(viewModel.webSocketSession)
            #expect(session.url.absoluteString == address)
            #expect(session.headers == [Header("Origin", "https://a.test")])
            #expect(session.messages == ["hello", "world"])
        }

        @Test(arguments: ["https://api.test/a", "ws://[::1"])
        func otherAddressesHaveNoSession(address: String) {
            let viewModel = ComposeViewModel()
            viewModel.address = address
            #expect(viewModel.webSocketSession == nil)
        }
    }
}
