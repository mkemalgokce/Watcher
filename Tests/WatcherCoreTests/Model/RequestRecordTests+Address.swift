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

        @Test(arguments: [
            ("::1", "https://[::1]/p"), ("fe80::1", "https://[fe80::1]/p"), ("a.test", "https://a.test/p"),
        ])
        func anIPv6HostIsBracketedInTheURL(host: String, url: String) {
            #expect(RequestRecord.fixture(host: host, path: "/p").url == url)
        }

        @Test(arguments: [("https", 443), ("wss", 443), ("http", 80), ("ws", 80), ("", 80)])
        func theDefaultPortIs443ForTLSSchemesAnd80Otherwise(scheme: String, port: Int) {
            #expect(RequestRecord.defaultPort(for: scheme) == port)
        }

        @Test(arguments: [("https", 443, true), ("http", 80, true), ("http", 443, false), ("ws", 80, false)])
        func onlyHTTPAndHTTPSOnTheirOwnPortUseTheDefault(scheme: String, port: Int, isDefault: Bool) {
            #expect(RequestRecord.fixture(scheme: scheme, port: port).usesDefaultPort == isDefault)
        }
    }
}

extension RequestRecordTests {
    struct PathWithoutQuery {
        @Test(arguments: [
            ("/a/b?x=1", "/a/b"), ("/a/b", "/a/b"), ("/?x=1", "/"), ("", "/"), ("?x=1", "/"),
            ("/a?b?c", "/a"), ("/a?", "/a"),
        ])
        func dropsTheQueryAndFallsBackToTheRoot(path: String, expected: String) {
            #expect(RequestRecord.fixture(path: path).pathWithoutQuery == expected)
            #expect(RequestRecord.pathWithoutQuery(of: path) == expected)
        }
    }
}
