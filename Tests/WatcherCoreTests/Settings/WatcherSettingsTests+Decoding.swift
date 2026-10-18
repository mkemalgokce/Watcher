import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension WatcherSettingsTests {
    struct Decoding {
        @Test
        func anEmptyDocumentDecodesToTheDefaults() throws {
            #expect(try JSONDecoder().decode(WatcherSettings.self, from: Data("{}".utf8)) == WatcherSettings())
        }

        @Test
        func everyChangedSettingSurvivesARoundTrip() throws {
            let settings = WatcherSettings.everythingChanged
            #expect(settings != WatcherSettings())
            #expect(try JSONDecoder().decode(WatcherSettings.self, from: JSONEncoder().encode(settings)) == settings)
        }
    }
}
