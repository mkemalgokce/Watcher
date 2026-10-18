import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ComposeViewModelTests {
    /// How the form becomes a request: the address, the authorization header and each kind of body.
    @MainActor
    struct Build {
        private func form(_ address: String = "https://api.example.com/x") -> ComposeViewModel {
            let viewModel = ComposeViewModel()
            viewModel.address = address
            return viewModel
        }

        private func body(_ request: RequestRecord) -> String {
            String(data: request.body, encoding: .utf8) ?? ""
        }

        @Test(arguments: [
            ("https://a.test", "https", "a.test", 443, "/"), ("http://a.test", "http", "a.test", 80, "/"),
            ("HTTPS://A.test/p", "https", "A.test", 443, "/p"), ("  https://a.test/p  ", "https", "a.test", 443, "/p"),
            ("http://a.test:8080/p?q=1", "http", "a.test", 8080, "/p?q=1"),
            ("https://a.test/a%20b?q=%26", "https", "a.test", 443, "/a%20b?q=%26"),
            ("https://a.test?x=1", "https", "a.test", 443, "/?x=1"),
        ])
        func anAddressBecomesSchemeHostPortAndPath(
            address: String, scheme: String, host: String, port: Int, path: String
        ) throws {
            let request = try form(address).build()
            #expect(request.scheme == scheme)
            #expect(request.host.lowercased() == host.lowercased())
            #expect(request.port == port)
            #expect(request.path == path)
        }

        @Test(arguments: ["", "https://", "ftp://a.test", "a.test/x", "http:///x", "ws://a.test", "not a url"])
        func anAddressWithoutAHostOrWithAnotherSchemeIsRefused(address: String) {
            #expect(throws: (any Error).self) { try form(address).build() }
        }

        @Test
        func theRefusalSaysWhatToEnter() {
            let error = #expect(throws: RequestBodyBuilder.BuildError.self) { try form("ftp://a.test").build() }
            #expect(error?.description == "Enter a full http:// or https:// URL.")
        }

        @Test
        func basicAuthIsTheBase64OfUserAndPassword() throws {
            let viewModel = form()
            viewModel.auth = .basic; viewModel.username = "ada"; viewModel.password = "p:w"
            let expected = "Basic " + Data("ada:p:w".utf8).base64EncodedString()
            #expect(try viewModel.build().headers.value(for: "Authorization") == expected)
        }

        @Test
        func basicAuthWithNoCredentialsStillSendsTheColon() throws {
            let viewModel = form()
            viewModel.auth = .basic
            #expect(try viewModel.build().headers.value(for: "Authorization") == "Basic Og==")
        }

        @Test
        func anEmptyBearerTokenAddsNothing() throws {
            let viewModel = form()
            viewModel.auth = .bearer
            #expect(try viewModel.build().headers.value(for: "Authorization") == nil)
        }

        @Test(arguments: [ComposeViewModel.Auth.bearer, .basic])
        func aHeaderTheUserWroteIsNotOverwrittenByAuth(auth: ComposeViewModel.Auth) throws {
            let viewModel = form()
            viewModel.auth = auth; viewModel.token = "t"
            viewModel.headers.append(KeyValue("authorization", "Mine"))
            let request = try viewModel.build()
            #expect(request.headers.filter { $0.name.lowercased() == "authorization" }.map(\.value) == ["Mine"])
        }

        @Test
        func aSwitchedOffAuthorizationHeaderDoesNotBlockAuth() throws {
            let viewModel = form()
            viewModel.auth = .bearer; viewModel.token = "t"
            viewModel.headers.append(KeyValue("Authorization", "Mine", isEnabled: false))
            #expect(try viewModel.build().headers.value(for: "Authorization") == "Bearer t")
        }

        @Test
        func switchedOffAndNamelessHeadersAreLeftOut() throws {
            let viewModel = form()
            viewModel.headers = [KeyValue("A", "1"), KeyValue("B", "2", isEnabled: false), KeyValue("", "3")]
            #expect(try viewModel.build().headers.map(\.name) == ["A"])
        }

        @Test(arguments: [
            (RequestBodyBuilder.Kind.json, "application/json"), (.text, "text/plain; charset=utf-8"),
            (.form, "application/x-www-form-urlencoded"), (.graphQL, "application/json"),
        ])
        func eachBodyKindSetsItsContentType(kind: RequestBodyBuilder.Kind, type: String) throws {
            let viewModel = form()
            viewModel.bodyKind = kind
            #expect(try viewModel.build().headers.value(for: "Content-Type") == type)
        }

        @Test
        func noBodyKindSendsNoBodyAndNoContentType() throws {
            let request = try form().build()
            #expect(request.body.isEmpty)
            #expect(request.headers.value(for: "Content-Type") == nil)
        }

        @Test
        func aContentTypeTheUserWroteWinsForTextBodies() throws {
            let viewModel = form()
            viewModel.bodyKind = .json; viewModel.bodyText = "{}"
            viewModel.headers.append(KeyValue("content-type", "application/vnd.api+json"))
            #expect(try viewModel.build().headers.filter { $0.name.lowercased() == "content-type" }.count == 1)
            #expect(try viewModel.build().headers.value(for: "content-type") == "application/vnd.api+json")
        }

        @Test
        func aFormBodyIsURLEncodedFromTheEnabledRows() throws {
            let viewModel = form()
            viewModel.bodyKind = .form
            viewModel.formRows = [KeyValue("a b", "x&y"), KeyValue("off", "1", isEnabled: false), KeyValue("c", "")]
            #expect(try body(viewModel.build()) == "a+b=x%26y&c=")
        }

        @Test
        func multipartReplacesTheContentTypeTheUserWroteWithOneThatMatchesTheBoundary() throws {
            let viewModel = form()
            viewModel.bodyKind = .multipart
            viewModel.formRows = [KeyValue("f", "v")]
            viewModel.headers.append(KeyValue("Content-Type", "multipart/form-data; boundary=stale"))
            let request = try viewModel.build()
            let type = try #require(request.headers.value(for: "Content-Type"))
            let boundary = try #require(type.components(separatedBy: "boundary=").last)
            #expect(boundary != "stale")
            #expect(body(request).contains("--\(boundary)--"))
            #expect(request.headers.filter { $0.name.lowercased() == "content-type" }.count == 1)
        }

        @Test
        func aGraphQLBodyCarriesTheQueryAndVariables() throws {
            let viewModel = form()
            viewModel.bodyKind = .graphQL
            viewModel.bodyText = "{ me { id } }"
            viewModel.graphQLVariables = #"{"id": 1}"#
            #expect(try body(viewModel.build()) == #"{"query":"{ me { id } }","variables":{"id":1}}"#)
        }

        @Test(arguments: ["[1]", "{", "text"])
        func graphQLVariablesThatAreNotAnObjectAreRefused(variables: String) {
            let viewModel = form()
            viewModel.bodyKind = .graphQL; viewModel.graphQLVariables = variables
            #expect(throws: RequestBodyBuilder.BuildError.self) { try viewModel.build() }
        }

        @Test
        func aBinaryBodyTakesItsContentTypeFromTheFileOnlyWhenNoneIsSet() throws {
            let viewModel = form()
            viewModel.bodyKind = .binary
            viewModel.file = .init(filename: "a.png", contentType: "image/png", data: Data([1, 2]))
            #expect(try viewModel.build().headers.value(for: "Content-Type") == "image/png")
            viewModel.headers.append(KeyValue("Content-Type", "application/x-custom"))
            let request = try viewModel.build()
            #expect(request.headers.value(for: "Content-Type") == "application/x-custom")
            #expect(request.body == Data([1, 2]))
        }

        @Test
        func theMethodIsKept() throws {
            let viewModel = form()
            viewModel.method = "PATCH"
            #expect(try viewModel.build().method == "PATCH")
        }
    }

    /// Loading a captured request into the form.
    @MainActor
    struct Load {
        private func loaded(_ request: RequestRecord, asOriginal: Bool = false) -> ComposeViewModel {
            let viewModel = ComposeViewModel()
            viewModel.load(request, asOriginal: asOriginal)
            return viewModel
        }

        @Test
        func aFormBodyBecomesRowsAndKeepsNoContentTypeHeader() {
            let request = RequestRecord.fixture(
                method: "POST",
                headers: [Header("Content-Type", "application/x-www-form-urlencoded"), Header("X", "1")],
                body: Data("a=1&b=two+words".utf8)
            )
            let viewModel = loaded(request)
            #expect(viewModel.bodyKind == .form)
            #expect(viewModel.formRows.map(\.name) == ["a", "b"])
            #expect(viewModel.formRows.map(\.value) == ["1", "two words"])
            #expect(viewModel.headers.map(\.name) == ["X"])
            #expect(viewModel.tab == .body)
        }

        @Test
        func aMultipartBodyBecomesTextAndFileRows() {
            let boundary = "B0"
            let part = KeyValue.FilePart(filename: "a.txt", contentType: "text/plain", data: Data("file!".utf8))
            let fields = [KeyValue("t", "hello"), KeyValue("f", "", file: part)]
            let request = RequestRecord.fixture(
                method: "POST", headers: [Header("Content-Type", "multipart/form-data; boundary=\(boundary)")],
                body: RequestBodyBuilder.multipart(fields, boundary: boundary)
            )
            let viewModel = loaded(request)
            #expect(viewModel.bodyKind == .multipart)
            #expect(viewModel.formRows.map(\.name) == ["t", "f"])
            #expect(viewModel.formRows[0].value == "hello")
            #expect(viewModel.formRows[1].file?.filename == "a.txt")
            #expect(viewModel.formRows[1].file?.data == Data("file!".utf8))
            #expect(viewModel.headers.contains { $0.name == "Content-Type" } == false)
        }

        @Test
        func aBinaryBodyBecomesAFile() {
            let bytes = Data([0xFF, 0xFE, 0x00, 0x80])
            let viewModel = loaded(.fixture(
                method: "PUT", headers: [Header("Content-Type", "application/octet-stream")], body: bytes
            ))
            #expect(viewModel.bodyKind == .binary)
            #expect(viewModel.file?.data == bytes)
            #expect(viewModel.file?.contentType == "application/octet-stream")
        }

        @Test
        func aGzipBodyIsShownDecodedWithoutItsEncodingHeader() {
            let request = RequestRecord.fixture(
                method: "POST",
                headers: [Header("Content-Type", "application/json"), Header("Content-Encoding", "gzip")],
                body: Data(#"{"a":1}"#.utf8).gzipped
            )
            let viewModel = loaded(request)
            #expect(viewModel.bodyText == #"{"a":1}"#)
            #expect(viewModel.headers.contains { $0.name == "Content-Encoding" } == false)
        }

        @Test
        func transportHeadersAreDropped() {
            let request = RequestRecord.fixture(
                headers: [Header("Host", "x"), Header("Content-Length", "3"), Header("Accept", "*/*")]
            )
            #expect(loaded(request).headers.map(\.name) == ["Accept"])
        }

        @Test
        func aRequestWithoutABodyOpensOnParams() {
            #expect(loaded(.fixture(path: "/x?a=1")).tab == .params)
        }

        @Test
        func theQueryBecomesParams() {
            #expect(loaded(.fixture(path: "/x?a=1&b=2")).params.map(\.name) == ["a", "b"])
        }

        @Test
        func onlyAnOriginalIsRemembered() {
            #expect(loaded(.fixture(), asOriginal: false).original == nil)
            #expect(loaded(.fixture(), asOriginal: true).original != nil)
        }
    }

    /// The red marker under a JSON body that cannot be parsed.
    @MainActor
    struct JSONValidity {
        @Test(arguments: [
            (RequestBodyBuilder.Kind.json, "", false), (.json, "1", false), (.json, "{}", false),
            (.json, "[1, 2]", false), (.json, "{", true), (.json, "nope", true), (.json, "{'a':1}", true),
            (.text, "{", false), (.none, "{", false),
        ])
        func aNonEmptyJSONBodyThatDoesNotParseIsInvalid(kind: RequestBodyBuilder.Kind, text: String, invalid: Bool) {
            let viewModel = ComposeViewModel()
            viewModel.bodyKind = kind; viewModel.bodyText = text
            #expect(viewModel.isBodyInvalidJSON == invalid)
        }
    }
}
