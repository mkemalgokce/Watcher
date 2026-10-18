import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct DeviceSetupTests {
        @Test
        func devicesOffersToTrustWhenNotTrusted() async throws {
            let model = try AppModel.test() // the test probe reports "not trusted" and no devices
            await withWindow(showing: DeviceSetupView().environment(model), width: 760, height: 560) { window in
                #expect(await window.shows("Not trusted yet"))
                #expect(await window.shows("Install & Trust…"), "the action that fixes it is right there")
                #expect(window.elements("Remove").isEmpty, "nothing to remove while not trusted")
            }
        }
    }
}
