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
        func theChangedFixtureMovesEverySettingOffItsDefault() {
            let defaults = Mirror(reflecting: WatcherSettings()).children
            let changed = Mirror(reflecting: WatcherSettings.everythingChanged).children
            for (fallback, moved) in zip(defaults, changed) {
                #expect(
                    String(describing: moved.value) != String(describing: fallback.value),
                    "\(moved.label ?? "?") still has its default"
                )
            }
        }

        @Test
        func everyChangedSettingSurvivesARoundTrip() throws {
            let settings = WatcherSettings.everythingChanged
            #expect(settings != WatcherSettings())
            #expect(try JSONDecoder().decode(WatcherSettings.self, from: JSONEncoder().encode(settings)) == settings)
        }
    }
}
