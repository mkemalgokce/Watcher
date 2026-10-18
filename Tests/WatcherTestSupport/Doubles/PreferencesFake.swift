import Foundation
import WatcherUI

/// User preferences kept in a dictionary, so tests never write the app's defaults domain.
public final class PreferencesFake: Preferences {
    public private(set) var values: [String: Any]

    public init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    public func object(forKey key: String) -> Any? {
        values[key]
    }

    public func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}
