import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ConverterTests {
    @Test
    func encodingsRoundTrip() throws {
        #expect(try Converter.run(.base64Decode, Converter.run(.base64Encode, "héllo wörld")) == "héllo wörld")
        #expect(try Converter.run(.urlDecode, Converter.run(.urlEncode, "a b&c=ü")) == "a b&c=ü")
        #expect(try Converter.run(.hexDecode, Converter.run(.hexEncode, "Watcher")) == "Watcher")
        #expect(try Converter.run(.jsonMinify, #"{ "a" : [1, 2] }"#) == #"{"a":[1,2]}"#)
        #expect(try Converter.run(.urlDecode, "a+b%21") == "a b!")
        #expect(try Converter.run(.hexEncode, "Wé") == "57c3a9")
    }

    @Test
    func timestampSecondsAndMilliseconds() throws {
        #expect(try Converter.run(.timestamp, "0").hasPrefix("1970-01-01T00:00:00Z"))
        let milliseconds = try Converter.run(.timestamp, "1700000000000")
        #expect(try milliseconds.prefix(20) == Converter.run(.timestamp, "1700000000").prefix(20))
    }

    @Test
    func invalidBase64SaysWhatIsWrong() {
        let error = #expect(throws: (any Error).self) { try Converter.run(.base64Decode, "***") }
        #expect(error.map { "\($0)" } == "This is not valid Base64.")
    }

    @Test(arguments: [
        (Converter.Operation.hexDecode, "abc"),
        (.jsonPretty, "{oops"),
        (.jwt, "abc.def.ghi"),
        (.urlEncode, "  "),
    ])
    func invalidInputThrows(operation: Converter.Operation, input: String) {
        #expect(throws: (any Error).self) { try Converter.run(operation, input) }
    }
}
