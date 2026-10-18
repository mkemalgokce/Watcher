import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The JSON Web Tokens an exchange carries in its headers, and how they stand at the injected time.
@Suite(.tags(.unit))
struct JWTSummaryTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func token(expiringIn seconds: TimeInterval?) -> String {
        func part(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        let claims = seconds.map { #"{"sub":"42","exp":\#(Int(now.timeIntervalSince1970 + $0))}"# } ?? #"{"sub":"42"}"#
        return part(#"{"alg":"HS256","typ":"JWT"}"#) + "." + part(claims) + ".sig"
    }

    private func summary(request: [String] = [], response: [String] = []) -> JWTSummary {
        let flow = Flow.fixture(
            request: .fixture(headers: request.map { Header("Authorization", "Bearer \($0)") }),
            response: .fixture(headers: response.map { Header("X-Token", $0) })
        )
        return JWTSummary(flow: flow, now: Self.now)
    }

    @Test
    func anExchangeWithoutTokensHasNothingToShow() {
        #expect(summary().tokens.isEmpty)
    }

    @Test
    func tokensAreFoundInBothSidesHeaders() {
        let found = summary(request: [Self.token(expiringIn: 60)], response: [Self.token(expiringIn: nil)])
        #expect(found.tokens.count == 2)
        #expect(found.title == "2 JWTs")
        #expect(summary(request: [Self.token(expiringIn: 60)]).title == "JWT")
    }

    @Test
    func aTokenPastItsExpiryAtTheInjectedTimeIsExpired() throws {
        let expired = summary(request: [Self.token(expiringIn: -3600)])
        #expect(expired.anyExpired)
        #expect(expired.help == "Carries an expired JSON Web Token. Click to decode it.")
        let expiry = try #require(expired.expiry(of: expired.tokens[0]))
        #expect(expiry.isExpired)
        #expect(expiry.text.hasPrefix("Expired "))
    }

    @Test
    func aTokenStillValidAtTheInjectedTimeSaysWhenItExpires() throws {
        let valid = summary(request: [Self.token(expiringIn: 3600)])
        #expect(!valid.anyExpired)
        #expect(valid.help == "Carries a JSON Web Token. Click to decode it.")
        let expiry = try #require(valid.expiry(of: valid.tokens[0]))
        #expect(!expiry.isExpired)
        #expect(expiry.text.hasPrefix("Expires "))
    }

    @Test
    func aTokenWithoutAnExpiryStatesNone() {
        let open = summary(request: [Self.token(expiringIn: nil)])
        #expect(open.expiry(of: open.tokens[0]) == nil)
        #expect(!open.anyExpired)
    }
}
