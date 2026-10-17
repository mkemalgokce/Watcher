@testable import WatcherCore
import XCTest

final class DeveloperToolsTests: XCTestCase {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52])

    func testFindsDataURIImageAndJSONValues() {
        let json = #"{"avatar":"data:image/png;base64,\#(png.base64EncodedString())","note":"\#(Data(#"{"alpha":1,"beta":[2]}"#.utf8).base64EncodedString())","id":"abc"}"#
        let found = Base64Finder.find(in: json)
        XCTAssertEqual(found.count, 2)
        guard found.count == 2 else { return }
        XCTAssertEqual(found[0].kind, .image(mime: "image/png")); XCTAssertEqual(found[0].data, png)
        XCTAssertEqual(found[1].kind, .text); XCTAssertEqual(found[1].label, "note"); XCTAssertTrue(found[1].text?.contains("\"alpha\": 1") == true)
        let ns = json as NSString
        XCTAssertEqual(ns.substring(with: found[0].range), png.base64EncodedString()) // ranges point at the encoded text only
    }

    func testWholeBodyBase64AndURLSafeAlphabet() {
        let message = "hello world, this is a long enough sentence?>>"
        let url = Data(message.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(Base64Finder.find(in: url).first?.text, message)
        XCTAssertTrue(Base64Finder.find(in: "short").isEmpty)
        XCTAssertTrue(Base64Finder.find(in: "just some ordinary sentence with spaces in it, nothing encoded").isEmpty)
    }

    func testBinaryAndImageSniffing() {
        let binary = Data((0 ..< 40).map { UInt8($0 * 7 % 251) } + [0, 1, 2])
        XCTAssertEqual(Base64Finder.find(in: binary.base64EncodedString()).first?.kind, .binary)
        XCTAssertEqual(Base64Finder.imageMime(Data([0xFF, 0xD8, 0xFF, 0xE0])), "image/jpeg")
        XCTAssertEqual(Base64Finder.imageMime(Data("<svg xmlns='x'/>".utf8)), "image/svg+xml")
        XCTAssertNil(Base64Finder.imageMime(Data("plain".utf8)))
    }

    func testJWT() throws {
        func b64(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        let token = "\(b64(#"{"alg":"HS256","typ":"JWT"}"#)).\(b64(#"{"sub":"42","exp":1000,"iat":900}"#)).sig"
        let jwt = try XCTUnwrap(JWT(token))
        XCTAssertTrue(jwt.header.contains("\"alg\" : \"HS256\"")); XCTAssertTrue(jwt.payload.contains("\"sub\" : \"42\""))
        XCTAssertEqual(jwt.expiresAt, Date(timeIntervalSince1970: 1000)); XCTAssertTrue(jwt.isExpired()); XCTAssertFalse(jwt.isExpired(at: Date(timeIntervalSince1970: 500)))
        XCTAssertEqual(JWT.find(in: "Authorization: Bearer \(token); again \(token)").count, 1) // duplicates collapse
        XCTAssertNil(JWT("not.a.token")); XCTAssertNil(JWT("a.b"))
    }

    func testCookies() {
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "h", port: 443, path: "/", headers: [Header("Cookie", "a=1; b=two=2")]))
        flow.response = ResponseRecord(status: 200, headers: [Header("Set-Cookie", "sid=xyz; Path=/; HttpOnly; Secure"), Header("set-cookie", "t=1; SameSite=Lax")])
        let cookies = Cookies.entries(for: flow)
        XCTAssertEqual(cookies.map(\.name), ["a", "b", "sid", "t"])
        XCTAssertEqual(cookies[1].value, "two=2")
        XCTAssertTrue(cookies[2].isSecure && cookies[2].isHttpOnly); XCTAssertFalse(cookies[3].isSecure)
        XCTAssertEqual(cookies[3].attributes, ["SameSite=Lax"])
    }
}

final class ConverterTests: XCTestCase {
    func testRoundTrips() throws {
        XCTAssertEqual(try Converter.run(.base64Decode, Converter.run(.base64Encode, "héllo wörld")), "héllo wörld")
        XCTAssertEqual(try Converter.run(.urlDecode, Converter.run(.urlEncode, "a b&c=ü")), "a b&c=ü")
        XCTAssertEqual(try Converter.run(.hexDecode, Converter.run(.hexEncode, "Watcher")), "Watcher")
        XCTAssertEqual(try Converter.run(.jsonMinify, #"{ "a" : [1, 2] }"#), #"{"a":[1,2]}"#)
        XCTAssertEqual(try Converter.run(.urlDecode, "a+b%21"), "a b!")
    }

    func testTimestampSecondsAndMilliseconds() throws {
        XCTAssertTrue(try Converter.run(.timestamp, "0").hasPrefix("1970-01-01T00:00:00Z"))
        XCTAssertEqual(try Converter.run(.timestamp, "1700000000000").prefix(20), try Converter.run(.timestamp, "1700000000").prefix(20))
    }

    func testErrorsSayWhatIsWrong() {
        XCTAssertThrowsError(try Converter.run(.base64Decode, "***")) { XCTAssertEqual("\($0)", "This is not valid Base64.") }
        XCTAssertThrowsError(try Converter.run(.hexDecode, "abc"))
        XCTAssertThrowsError(try Converter.run(.jsonPretty, "{oops"))
        XCTAssertThrowsError(try Converter.run(.jwt, "abc.def.ghi"))
        XCTAssertThrowsError(try Converter.run(.urlEncode, "  "))
    }
}

final class FormFieldTests: XCTestCase {
    func testMultipartFileKeepsItsBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        var body = Data("--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello\r\n--B\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        body.append(png); body.append(Data("\r\n--B--\r\n".utf8))
        let request = RequestRecord(method: "POST", scheme: "https", host: "h", port: 443, path: "/up?x=1", headers: [Header("Content-Type", "multipart/form-data; boundary=B")], body: body)
        let fields = FormFields.parse(request)
        XCTAssertEqual(fields.map(\.name), ["x", "title", "avatar"])
        XCTAssertNil(fields[1].data)
        XCTAssertEqual(fields[2].data, png); XCTAssertEqual(fields[2].contentType, "image/png"); XCTAssertEqual(fields[2].filename, "a.png")
    }
}
