/// Small settings kept between launches outside ~/.watcher: the view preferences and first-run state.
public protocol Preferences: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}
