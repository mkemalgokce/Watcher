import ArgumentParser
import WatcherCore

enum PortOption {
    /// Accepts no `--port` or one a socket can use; `allowsAny` also takes 0, which lets the system pick a free one.
    static func validate(_ port: Int?, allowsAny: Bool = false) throws {
        guard let port, !PortRange.isValid(port), !(allowsAny && port == 0) else { return }
        throw ValidationError("--port must be from \(allowsAny ? 0 : 1) to 65535.")
    }
}
