import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ThrottleSettingsTests {
    struct Decoding {
        @Test
        func anEmptyDocumentDecodesToTheDefaults() throws {
            #expect(try JSONDecoder().decode(ThrottleSettings.self, from: Data("{}".utf8)) == ThrottleSettings())
        }

        @Test
        func everyFieldSurvivesARoundTrip() throws {
            let settings = ThrottleSettings(
                isEnabled: true,
                profile: NetworkProfile.presets[2],
                host: "h:1",
                customProfiles: [NetworkProfile(name: "mine")]
            )
            #expect(try JSONDecoder().decode(ThrottleSettings.self, from: JSONEncoder().encode(settings)) == settings)
        }
    }
}
