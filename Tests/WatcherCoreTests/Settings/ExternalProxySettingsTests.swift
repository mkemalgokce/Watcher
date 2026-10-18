import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ExternalProxySettingsTests {
    @Test
    func anEmptyDocumentDecodesToTheDefaults() throws {
        #expect(try JSONDecoder().decode(ExternalProxySettings.self, from: Data("{}".utf8)) == ExternalProxySettings())
    }

    @Test
    func missingKeysKeepTheirDefaultsNextToPresentOnes() throws {
        let json = Data(#"{"kind":"pac","port":3128}"#.utf8)
        let settings = try JSONDecoder().decode(ExternalProxySettings.self, from: json)
        #expect(settings == ExternalProxySettings(kind: .pac, port: 3128))
    }
}
