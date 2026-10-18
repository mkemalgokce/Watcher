/// Preferences kept in a dictionary for one run: previews and tests use it so they never write the app's defaults domain.
public final class InMemoryPreferences: Preferences {
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
