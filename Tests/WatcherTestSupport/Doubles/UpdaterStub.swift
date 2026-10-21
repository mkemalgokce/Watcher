import WatcherUI

/// The app's updater in memory: it counts the checks and keeps the automatic-check switch it was last given.
@MainActor
public final class UpdaterStub {
    public private(set) var checks = 0
    public private(set) var checksAutomatically: Bool

    public init(checksAutomatically: Bool = false) {
        self.checksAutomatically = checksAutomatically
    }

    public var updater: AppUpdater {
        AppUpdater(
            check: { [self] in checks += 1 },
            checksAutomatically: { [self] in checksAutomatically },
            setChecksAutomatically: { [self] enabled in checksAutomatically = enabled }
        )
    }
}
