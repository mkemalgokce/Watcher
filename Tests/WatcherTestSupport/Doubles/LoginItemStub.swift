import Foundation
import WatcherUI

/// The Mac's login item for this app, in memory: it reports what was last set, or refuses changes when told to.
@MainActor
public final class LoginItemStub {
    public struct Failure: LocalizedError {
        public var errorDescription: String? {
            "not a bundled app"
        }
    }

    public private(set) var isEnabled: Bool
    private let failing: Bool

    public init(isEnabled: Bool = false, failing: Bool = false) {
        self.isEnabled = isEnabled; self.failing = failing
    }

    public var loginItem: LoginItem {
        LoginItem(isEnabled: { [self] in isEnabled }, setEnabled: { [self] enabled in
            if failing {
                throw Failure()
            }
            isEnabled = enabled
        })
    }
}
