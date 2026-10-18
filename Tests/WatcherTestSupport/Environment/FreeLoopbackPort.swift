/// A port on 127.0.0.1 that is free right now, for a port nobody listens on, such as a refused connection; listeners
/// that can bind to 0 do that and report their port.
public func freeLoopbackPort() throws -> Int {
    try LoopbackSocket().port
}
