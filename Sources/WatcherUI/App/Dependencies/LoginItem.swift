/// Whether macOS opens Watcher at login. macOS owns the setting, so it is read back rather than stored.
public struct LoginItem {
    public var isEnabled: @MainActor () -> Bool
    public var setEnabled: @MainActor (Bool) throws -> Void

    public init(isEnabled: @escaping @MainActor () -> Bool, setEnabled: @escaping @MainActor (Bool) throws -> Void) {
        self.isEnabled = isEnabled; self.setEnabled = setEnabled
    }
}
