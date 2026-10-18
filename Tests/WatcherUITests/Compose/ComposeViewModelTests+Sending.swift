import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ComposeViewModelTests {
    /// Sending, the tab badges and the body checks around it.
    @MainActor
    struct Sending {
        private func viewModel(boundary: String = "B") -> ComposeViewModel {
            let viewModel = ComposeViewModel(boundary: { boundary })
            viewModel.address = "https://api.example.com/x"
            return viewModel
        }

        @Test
        func aMultipartBodyUsesTheBoundaryItWasGiven() throws {
            let viewModel = viewModel(boundary: "FIXED")
            viewModel.bodyKind = .multipart
            viewModel.formRows = [KeyValue("a", "1")]
            let request = try viewModel.build()
            #expect(request.body == RequestBodyBuilder.multipart(viewModel.formRows, boundary: "FIXED"))
            #expect(request.headers.value(for: "Content-Type") == "multipart/form-data; boundary=FIXED")
        }

        @Test
        func aLoadedMultipartRequestShowsNoChangesUntilItIsEdited() throws {
            let source = viewModel(boundary: "FIXED")
            source.bodyKind = .multipart
            source.formRows = [KeyValue("a", "1")]
            let original = try source.build()

            let editing = viewModel(boundary: "OTHER")
            editing.load(original, asOriginal: true)
            #expect(editing.changes.isEmpty)
            editing.formRows[0].value = "2"
            #expect(editing.changes.isEmpty, "a multipart body is not compared byte for byte")
        }

        @Test
        func switchedOffParametersSurviveAnAddressEdit() {
            let viewModel = viewModel()
            viewModel.address = "https://api.example.com/x?a=1&b=2"
            viewModel.params[0].isEnabled = false
            viewModel.address = "https://api.example.com/x?b=3"
            #expect(viewModel.params.map(\.name) == ["b", "a"])
            #expect(viewModel.params.map(\.isEnabled) == [true, false])
            #expect(viewModel.params[0].value == "3")
        }

        @Test
        func parametersWithoutANameAreLeftOutOfTheAddress() {
            let viewModel = viewModel()
            viewModel.params = [KeyValue("", "x"), KeyValue("a", "1")]
            #expect(viewModel.address == "https://api.example.com/x?a=1")
        }

        @Test(arguments: [(499, false), (500, true), (503, true), (200, false)])
        func onlyServerErrorsAddANote(status: Int, noted: Bool) async {
            let viewModel = viewModel()
            await viewModel.send(isProxyRunning: true) { _, _ in .fixture(status: status) }
            #expect((viewModel.problem != nil) == noted)
        }

        @Test
        func aSecondSendWhileOneIsRunningIsIgnored() async {
            let gate = SleepGate()
            let viewModel = viewModel()
            let first = Task {
                await viewModel.send(isProxyRunning: true) { _, _ in
                    try? await gate.sleep(.zero)
                    return .fixture(status: 200)
                }
            }
            #expect(await eventually { viewModel.isSending })
            await viewModel.send(isProxyRunning: true) { _, _ in
                Issue.record("a second send must not start")
                return .fixture()
            }
            gate.releaseAll()
            await first.value
            #expect(viewModel.result?.response?.status == 200)
        }

        @Test
        func aBuildErrorBecomesTheFailedPhase() async {
            let viewModel = viewModel()
            viewModel.address = "ftp://example.com"
            await viewModel.send(isProxyRunning: true) { _, _ in .fixture() }
            #expect(viewModel.phase == .failed("Enter a full http:// or https:// URL."))
        }

        @Test
        func webSocketMessagesSkipBlankLines() {
            let viewModel = viewModel()
            viewModel.bodyText = "one\n\ntwo\n"
            #expect(viewModel.webSocketMessages == ["one", "two"])
        }

        @Test(arguments: [
            (RequestBodyBuilder.Kind.json, "", false), (.json, "1", false), (.json, "{", true),
            (.json, #"{"a":1}"#, false), (.text, "{", false), (.none, "{", false),
        ])
        func onlyAJSONBodyThatDoesNotParseIsInvalid(kind: RequestBodyBuilder.Kind, text: String, invalid: Bool) {
            let viewModel = viewModel()
            viewModel.bodyKind = kind
            viewModel.bodyText = text
            #expect(viewModel.isBodyInvalidJSON == invalid)
        }

        @Test
        func theBadgesCountSwitchedOnRowsAndNameTheBody() {
            let viewModel = viewModel()
            viewModel.headers = [KeyValue("A", "1"), KeyValue("B", "2", isEnabled: false)]
            #expect(viewModel.badge(.headers) == "1")
            #expect(viewModel.badge(.params) == nil)
            #expect(viewModel.badge(.auth) == nil)
            #expect(viewModel.badge(.body) == nil)
            viewModel.auth = .bearer
            viewModel.bodyKind = .json
            #expect(viewModel.badge(.auth) == "●")
            #expect(viewModel.badge(.body) == RequestBodyBuilder.Kind.json.rawValue)
        }
    }
}
