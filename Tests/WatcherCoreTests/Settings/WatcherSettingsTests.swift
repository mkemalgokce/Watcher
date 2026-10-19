import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct WatcherSettingsTests {
    @Test
    func settingsWrittenBeforeCertificatesAndTemplatesExistedStillLoad() throws {
        let old = try JSONDecoder().decode(WatcherSettings.self, from: Data(#"{"port": 1}"#.utf8))
        #expect(old.customCertificates.rules.isEmpty && old.breakpointTemplates.isEmpty)
    }

    @Test
    func missingFieldsTakeTheirDefaults() throws {
        let defaults = try JSONDecoder().decode(WatcherSettings.self, from: Data("{}".utf8))
        #expect(defaults.preferHTTP2 && defaults.mcpRedaction)
        #expect(
            !(defaults.listenOnIPv6 || defaults.autoIgnoreSSLPinning || defaults.hideAppleTraffic
                || defaults.hideSystemServices
                || defaults.autoSystemProxy)
        )
        let numbers = [defaults.leafCertificateValidityDays, defaults.maxFlows, defaults.composeTimeoutSeconds]
        #expect(numbers == [365, 0, 60])
    }
}
