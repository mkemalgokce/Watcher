import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RequestBodyBuilderTests {
    @Test
    func urlEncodedSkipsDisabledAndEmptyRows() {
        let data = RequestBodyBuilder.urlEncoded([
            KeyValue("q", "a b&c"),
            KeyValue("off", "1", isEnabled: false),
            KeyValue("", "x"),
            KeyValue("ü", "="),
        ])
        #expect(String(bytes: data, encoding: .utf8) == "q=a+b%26c&%C3%BC=%3D")
    }

    /// What the builder writes, the multipart parser reads back: text fields and file bytes survive the round trip.
    @Test
    func multipartRoundTrip() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0, 1, 2])
        let boundary = RequestBodyBuilder.newBoundary()
        let body = RequestBodyBuilder.multipart([
            KeyValue("title", "Holiday"),
            KeyValue("photo", "", file: .init(filename: "a.png", contentType: "image/png", data: png)),
            KeyValue("skip", "x", isEnabled: false),
        ], boundary: boundary)
        let contentType = try #require(RequestBodyBuilder.contentType(for: .multipart, boundary: boundary))
        let request = RequestRecord.fixture(
            method: "POST",
            host: "h",
            headers: [Header("Content-Type", contentType)],
            body: body
        )
        let fields = FormFields.parse(request)
        #expect(fields.map(\.name) == ["title", "photo"])
        #expect(fields[0].value == "Holiday")
        #expect(fields[1].data == png); #expect(fields[1].filename == "a.png")
        #expect(fields[1].contentType == "image/png")
    }

    @Test
    func graphQLWrapsQueryAndVariables() throws {
        let data = try RequestBodyBuilder.graphQL(query: "query { me { id } }", variables: #"{"id": 1}"#)
        #expect(String(bytes: data, encoding: .utf8) == #"{"query":"query { me { id } }","variables":{"id":1}}"#)
        #expect(throws: (any Error).self) { try RequestBodyBuilder.graphQL(query: "q", variables: "[1]") }
        let withoutVariables = try RequestBodyBuilder.graphQL(query: "q", variables: "  ")
        #expect(String(bytes: withoutVariables, encoding: .utf8) == #"{"query":"q"}"#)
    }

    @Test(arguments: [
        (String?("multipart/form-data; boundary=x"), Data([1]), RequestBodyBuilder.Kind.multipart),
        ("application/x-www-form-urlencoded", Data("a=1".utf8), .form),
        ("application/json", Data("{}".utf8), .json),
        (nil, Data(), .none),
        ("application/octet-stream", Data([0xFF, 0xFE, 0x00, 0xD8]), .binary),
    ])
    func kindDetection(contentType: String?, body: Data, kind: RequestBodyBuilder.Kind) {
        #expect(RequestBodyBuilder.kind(forContentType: contentType, body: body) == kind)
    }
}
