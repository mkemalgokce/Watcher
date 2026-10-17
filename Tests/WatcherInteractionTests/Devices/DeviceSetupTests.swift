import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct DeviceSetupTests {
        @Test
        func devicesOffersToTrustWhenNotTrusted() async {
            let model = AppModel(listening: false) // the test probe reports "not trusted" and no devices
            await withWindow(showing: DeviceSetupView().environment(model), width: 760, height: 560) { window in
                #expect(!window.elements("Not trusted yet").isEmpty)
                #expect(!window.elements("Install & Trust…").isEmpty, "the action that fixes it is right there")
                #expect(window.elements("Remove").isEmpty, "nothing to remove while not trusted")
            }
        }
    }
}
