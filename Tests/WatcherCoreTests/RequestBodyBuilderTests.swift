@testable import WatcherCore
import XCTest

final class RequestBodyBuilderTests: XCTestCase {
    func testURLEncodedSkipsDisabledAndEmptyRows() {
        let data = RequestBodyBuilder.urlEncoded([KeyValue("q", "a b&c"), KeyValue("off", "1", isEnabled: false), KeyValue("", "x"), KeyValue("ü", "=")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "q=a+b%26c&%C3%BC=%3D")
    }

    /// What the builder writes, the multipart parser reads back: text fields and file bytes survive the round trip.
    func testMultipartRoundTrip() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0, 1, 2])
        let boundary = RequestBodyBuilder.newBoundary()
        let body = RequestBodyBuilder.multipart([
            KeyValue("title", "Holiday"),
            KeyValue("photo", "", file: .init(filename: "a.png", contentType: "image/png", data: png)),
            KeyValue("skip", "x", isEnabled: false),
        ], boundary: boundary)
        let request = try RequestRecord(
            method: "POST",
            scheme: "https",
            host: "h",
            port: 443,
            path: "/",
            headers: [Header("Content-Type", XCTUnwrap(RequestBodyBuilder.contentType(for: .multipart, boundary: boundary)))],
            body: body
        )
        let fields = FormFields.parse(request)
        XCTAssertEqual(fields.map(\.name), ["title", "photo"])
        XCTAssertEqual(fields[0].value, "Holiday")
        XCTAssertEqual(fields[1].data, png); XCTAssertEqual(fields[1].filename, "a.png"); XCTAssertEqual(fields[1].contentType, "image/png")
    }

    func testGraphQL() throws {
        let data = try RequestBodyBuilder.graphQL(query: "query { me { id } }", variables: #"{"id": 1}"#)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"query":"query { me { id } }","variables":{"id":1}}"#)
        XCTAssertThrowsError(try RequestBodyBuilder.graphQL(query: "q", variables: "[1]"))
        XCTAssertEqual(try String(decoding: RequestBodyBuilder.graphQL(query: "q", variables: "  "), as: UTF8.self), #"{"query":"q"}"#)
    }

    func testKindDetection() {
        XCTAssertEqual(RequestBodyBuilder.kind(forContentType: "multipart/form-data; boundary=x", body: Data([1])), .multipart)
        XCTAssertEqual(RequestBodyBuilder.kind(forContentType: "application/x-www-form-urlencoded", body: Data("a=1".utf8)), .form)
        XCTAssertEqual(RequestBodyBuilder.kind(forContentType: "application/json", body: Data("{}".utf8)), .json)
        XCTAssertEqual(RequestBodyBuilder.kind(forContentType: nil, body: Data()), .none)
        XCTAssertEqual(RequestBodyBuilder.kind(forContentType: "application/octet-stream", body: Data([0xFF, 0xFE, 0x00, 0xD8])), .binary)
    }
}

final class EventStreamTests: XCTestCase {
    func testParsesEventsLikeEventSource() {
        let text = ": keep-alive\r\nid: 1\r\nevent: price\r\ndata: {\"a\":1}\r\n\r\ndata: line one\ndata: line two\n\nretry: 3000\nevent: done\n"
        let events = EventStream.parse(text)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .init(id: "1", event: "price", data: #"{"a":1}"#, retry: nil))
        XCTAssertEqual(events[1].data, "line one\nline two"); XCTAssertNil(events[1].event)
        XCTAssertEqual(events[2].event, "done"); XCTAssertEqual(events[2].retry, 3000); XCTAssertEqual(events[2].data, "")
        XCTAssertTrue(EventStream.parse("").isEmpty)
    }
}
