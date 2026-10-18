import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct JWTTests {
    @Test
    func decodesHeaderPayloadAndExpiryAndFindsTokensOnce() throws {
        func b64(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        let token = "\(b64(#"{"alg":"HS256","typ":"JWT"}"#)).\(b64(#"{"sub":"42","exp":1000,"iat":900}"#)).sig"
        let jwt = try #require(JWT(token))
        #expect(jwt.header.contains("\"alg\" : \"HS256\"")); #expect(jwt.payload.contains("\"sub\" : \"42\""))
        #expect(jwt.expiresAt == Date(timeIntervalSince1970: 1000))
        #expect(jwt.isExpired()); #expect(!jwt.isExpired(at: Date(timeIntervalSince1970: 500)))
        #expect(JWT.find(in: "Authorization: Bearer \(token); again \(token)").count == 1, "duplicates collapse")
        #expect(JWT("not.a.token") == nil); #expect(JWT("a.b") == nil)
    }
}
