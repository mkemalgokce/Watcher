import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@MainActor
@Suite(.tags(.unit))
struct ConverterViewModelTests {
    @Test
    func aConversionShowsItsResultAndIsMarkedConverted() {
        let converter = ConverterViewModel()
        converter.operation = .base64Encode
        converter.input = "hi"
        #expect(converter.output == "aGk=")
        #expect(converter.failure == nil)
        #expect(converter.isConverted)
    }

    @Test(arguments: ["", " ", "\n\t  "])
    func blankInputConvertsToNothingAndIsNotMarkedConverted(blank: String) {
        let converter = ConverterViewModel()
        converter.input = "aGk="
        #expect(converter.isConverted)
        converter.input = blank
        #expect(converter.output.isEmpty)
        #expect(converter.failure == nil)
        #expect(!converter.isConverted)
    }

    @Test
    func aFailureShowsItsMessageAndClearsTheResult() {
        let converter = ConverterViewModel()
        converter.input = "aGk="
        converter.input = "!!not base64!!"
        #expect(converter.output.isEmpty)
        #expect(converter.failure?.isEmpty == false)
        #expect(!converter.isConverted)
    }

    @Test
    func switchingTheOperationConvertsTheSameInputAgain() {
        let converter = ConverterViewModel()
        converter.input = "hi"
        converter.operation = .hexEncode
        #expect(converter.output == "6869")
        converter.operation = .base64Encode
        #expect(converter.output == "aGk=")
    }

    @Test
    func theResultCanBecomeTheInput() {
        let converter = ConverterViewModel()
        converter.operation = .base64Encode
        converter.input = "hi"
        converter.useResultAsInput()
        #expect(converter.input == "aGk=")
    }

    @Test
    func pasteTakesTheClipboardTextButKeepsTheInputWhenItIsEmpty() {
        let converter = ConverterViewModel()
        converter.operation = .base64Encode
        converter.paste(from: ClipboardSpy(text: "hi"))
        #expect(converter.input == "hi")
        converter.paste(from: ClipboardSpy(text: nil))
        #expect(converter.input == "hi")
    }
}
