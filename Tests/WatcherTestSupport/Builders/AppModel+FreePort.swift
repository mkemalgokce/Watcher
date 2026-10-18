import WatcherCore
@testable import WatcherUI

public extension AppModel {
    /// Points the proxy at the first free port from `start`, so a test cannot clash with a running Watcher.
    @MainActor
    func useFreePort(searchingFrom start: Int, fallback: Int) throws {
        settings.value.port = PortFinder.firstAvailable(from: start) ?? fallback
        try engine.settings.replace(with: settings.value)
    }
}
