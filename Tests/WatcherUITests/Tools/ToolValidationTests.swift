import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Rule mistakes Tools warns about, so a rule never fails silently.
@Suite(.tags(.unit))
struct ToolValidationTests {
    @Test
    func anEmptyPatternOrABrokenRegexIsAProblem() {
        #expect(ToolValidation.problems(MatchingRule(pattern: "api.example.com/*")) == [])
        #expect(ToolValidation.problems(MatchingRule(pattern: "  ")).count == 1, "empty matches everything")
        var regex = MatchingRule(pattern: "api\\.example\\.com/v[0-9]+")
        regex.mode = .regex
        #expect(ToolValidation.problems(regex) == [])
        regex.pattern = "api.example.com/(v1"
        #expect(ToolValidation.problems(regex).count == 1, "an unbalanced group does not compile")
    }

    @Test
    func aDNSRuleNeedsAPlainHostAndAnIPAddress() {
        func problems(_ host: String, _ address: String) -> [String] {
            ToolValidation.problems(DNSSpoofRule(host: host, address: address))
        }
        #expect(problems("api.example.com", "127.0.0.1") == [])
        #expect(problems("api.example.com", "::1") == [], "IPv6 is fine")
        #expect(problems("api.example.com", "256.1.1.1").count == 1)
        #expect(problems("api.example.com", "localhost").count == 1, "a name is not an address")
        #expect(problems("https://api.example.com/", "10.0.0.1").count == 1)
        #expect(problems("*.example.com", "10.0.0.1").count == 1)
        #expect(problems("", "").count == 2)
    }

    @Test
    func aReverseProxyNeedsItsOwnFreePortAndARemoteHost() {
        let rule = ReverseProxyRule(localPort: 9191, remoteHost: "api.example.com")
        #expect(ToolValidation.problems(rule, proxyPort: 9090, others: []) == [])
        let onProxyPort = ReverseProxyRule(localPort: 9090, remoteHost: "x")
        #expect(ToolValidation.problems(onProxyPort, proxyPort: 9090, others: []).count == 1)
        let samePort = ReverseProxyRule(localPort: 9191, remoteHost: "other")
        #expect(ToolValidation.problems(rule, proxyPort: 9090, others: [samePort]).count == 1)
        var disabled = ReverseProxyRule(localPort: 9191, remoteHost: "other"); disabled.isEnabled = false
        #expect(
            ToolValidation.problems(rule, proxyPort: 9090, others: [disabled]) == [],
            "a switched-off rule does not hold the port"
        )
        let blankHost = ReverseProxyRule(localPort: 9191, remoteHost: " ")
        #expect(ToolValidation.problems(blankHost, proxyPort: 9090, others: []).count == 1)
    }

    @Test
    func aCertificateRuleNeedsAHostAndAnExistingFile() {
        let rule = CustomCertificateRule(host: "api.example.com", role: .client, p12Path: "~/certs/client.p12")
        #expect(
            ToolValidation.problems(rule) { $0.hasSuffix("/certs/client.p12") && !$0.hasPrefix("~") } == [],
            "~ is expanded"
        )
        #expect(ToolValidation.problems(rule, fileExists: { _ in false }) == ["No file at ~/certs/client.p12."])
        #expect(ToolValidation.problems(CustomCertificateRule(host: "", role: .server, p12Path: "")).count == 2)
    }
}
