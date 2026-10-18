import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct ConverterTests {
        @Test
        func converterDecodesWhatIsTyped() async throws {
            let model = try AppModel.test()
            await withWindow(showing: ConverterView().environment(model), width: 640, height: 500) { window in
                #expect(await window.type("aGVsbG8gd2F0Y2hlcg==", role: "AXTextArea"), "the input field accepts text")
                #expect(!window.elements("Converted").isEmpty, "a successful conversion says so")
                #expect(await window.type("%%% not base64", intoFieldWithValue: "aGVs", role: "AXTextArea"))
                #expect(!window.elements("This is not valid Base64.").isEmpty, "bad input is explained, not ignored")
            }
        }
    }
}
