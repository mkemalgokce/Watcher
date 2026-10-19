/// What sort of program, or machine, sent a request.
public enum ClientKind: String, Codable, Sendable, CaseIterable {
    case app, tool, service, device
}

/// Who sent a request: the owner shown to people, plus the raw process it came from.
public struct ClientIdentity: Equatable, Sendable {
    /// Display and owner name: the app for helpers, the process otherwise, the peer address for a device.
    public let app: String
    /// The raw command name, as `lsof` reports it.
    public let process: String
    public let kind: ClientKind
    /// Outermost `.app` folder, when the executable lives in one.
    public let bundlePath: String?

    public init(app: String, process: String, kind: ClientKind, bundlePath: String?) {
        self.app = app; self.process = process; self.kind = kind; self.bundlePath = bundlePath
    }

    /// A client on another machine, known only by its address.
    static func device(address: String) -> ClientIdentity {
        ClientIdentity(app: address, process: address, kind: .device, bundlePath: nil)
    }
}
