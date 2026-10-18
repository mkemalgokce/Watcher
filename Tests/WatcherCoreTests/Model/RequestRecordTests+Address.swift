import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension RequestRecordTests {
    struct Address {
        @Test(arguments: [
            ("https", 443, "https://h/p"),
            ("http", 80, "http://h/p"),
            ("http", 443, "http://h:443/p"),
            ("https", 80, "https://h:80/p"),
            ("https", 8443, "https://h:8443/p"),
            ("ws", 80, "ws://h:80/p"),
        ])
        func defaultPortsAreLeftOutOfTheURL(scheme: String, port: Int, url: String) {
            #expect(RequestRecord.fixture(scheme: scheme, host: "h", port: port, path: "/p").url == url)
        }
    }
}
