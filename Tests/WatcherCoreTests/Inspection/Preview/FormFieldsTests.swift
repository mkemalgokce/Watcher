import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct FormFieldsTests {
    @Test
    func multipartFileKeepsItsBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        var body = Data((
            "--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello\r\n"
                + "--B\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\n"
                + "Content-Type: image/png\r\n\r\n"
        ).utf8)
        body.append(png); body.append(Data("\r\n--B--\r\n".utf8))
        let request = RequestRecord.fixture(
            method: "POST",
            host: "h",
            path: "/up?x=1",
            headers: [Header("Content-Type", "multipart/form-data; boundary=B")],
            body: body
        )
        let fields = FormFields.parse(request)
        #expect(fields.map(\.name) == ["x", "title", "avatar"])
        #expect(fields[1].data == nil)
        #expect(fields[2].data == png); #expect(fields[2].contentType == "image/png")
        #expect(fields[2].filename == "a.png")
    }

    @Test
    func queryUrlencodedAndMultipartFieldsAreListed() {
        let form = RequestRecord.fixture(
            method: "POST",
            host: "a.com",
            path: "/submit?debug=1&q=a%20b",
            headers: [Header("Content-Type", "application/x-www-form-urlencoded")],
            body: Data("name=Ada+L&city=Z%C3%BCrich".utf8)
        )
        #expect(
            FormFields.parse(form).map { "\($0.source.rawValue):\($0.name)=\($0.value)" }
                == ["query:debug=1", "query:q=a b", "form:name=Ada L", "form:city=Zürich"]
        )

        let body = "--XX\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello\r\n"
            + "--XX\r\nContent-Disposition: form-data; name=\"upload\"; filename=\"a.png\"\r\n"
            + "Content-Type: image/png\r\n\r\n\u{1}\u{2}\u{3}\r\n--XX--\r\n"
        let multipart = RequestRecord.fixture(
            method: "POST",
            host: "a.com",
            path: "/u",
            headers: [Header("Content-Type", "multipart/form-data; boundary=XX")],
            body: Data(body.utf8)
        )
        let fields = FormFields.parse(multipart)
        #expect(fields.map(\.name) == ["title", "upload"])
        #expect(fields[0].value == "hello")
        #expect(fields[1].filename == "a.png")
        #expect(fields[1].value == "image/png, 3 bytes")
        #expect(FormFields.parse(RequestRecord.fixture(host: "a")).isEmpty)
    }

    @Test(arguments: [
        ("q=hello world", ["q=hello world"]),
        ("q=100%", ["q=100%"]),
        ("q=caf\u{E9}", ["q=caf\u{E9}"]),
        ("a=%41&&b", ["a=A", "=", "b="]),
        ("a=b=c&", ["a=b=c", "="]),
        ("", []),
    ])
    func aUrlencodedBodyThatIsNotAValidQueryStillListsItsFields(body: String, fields: [String]) {
        let request = RequestRecord.fixture(
            method: "POST",
            headers: [Header("Content-Type", "application/x-www-form-urlencoded")],
            body: Data(body.utf8)
        )
        #expect(FormFields.parse(request).map { "\($0.name)=\($0.value)" } == fields)
    }

    @Test(arguments: [
        ("a=two+words", "two words"), ("a=two%20words", "two words"), ("a=1%2B1", "1+1"), ("a=%zz", "%zz"),
    ])
    func aFormBodyDecodesPlusAsSpaceAndPercentEscapes(body: String, value: String) {
        let request = RequestRecord.fixture(
            method: "POST",
            headers: [Header("Content-Type", "application/x-www-form-urlencoded")],
            body: Data(body.utf8)
        )
        #expect(FormFields.parse(request).map(\.value) == [value])
    }

    @Test(arguments: [
        ("application/x-www-form-urlencoded", "a=1&b=x+y", ["form:a=1", "form:b=x y"]),
        ("Application/X-WWW-Form-Urlencoded; charset=utf-8", "a=%C3%BC", ["form:a=ü"]),
        ("application/x-www-form-urlencoded", "", []),
        ("application/json", "a=1", []),
        ("multipart/form-data", "a=1", []),
        (
            "multipart/form-data; boundary=B",
            "--B\r\nContent-Disposition: form-data; name=\"t\"\r\n\r\nhi\r\n--B--\r\n",
            ["multipart:t=hi"]
        ),
    ])
    func aBodyAloneIsParsedByItsContentType(type: String, body: String, expected: [String]) {
        let fields = FormFields.parse(body: Data(body.utf8), contentType: type)
        #expect(fields.map { "\($0.source.rawValue):\($0.name)=\($0.value)" } == expected)
    }

    @Test
    func aBodyWithoutAContentTypeHasNoFields() {
        #expect(FormFields.parse(body: Data("a=1".utf8), contentType: nil).isEmpty)
    }
}
