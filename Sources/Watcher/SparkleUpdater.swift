import Foundation
import Sparkle
import WatcherUI

extension AppUpdater {
    /// Sparkle over the feed and public key in the app's Info.plist; nil in a build without them, which has nothing to
    /// update from.
    @MainActor
    static func sparkle(info: [String: Any]? = Bundle.main.infoDictionary) -> AppUpdater? {
        guard UpdateConfiguration.isConfigured(info) else { return nil }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        let updater = controller.updater
        return AppUpdater(
            check: { controller.checkForUpdates(nil) },
            checksAutomatically: { updater.automaticallyChecksForUpdates },
            setChecksAutomatically: { updater.automaticallyChecksForUpdates = $0 }
        )
    }
}
