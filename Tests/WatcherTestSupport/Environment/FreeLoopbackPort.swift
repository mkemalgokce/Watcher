import Foundation

/// A port on 127.0.0.1 the system just handed out, for listeners that cannot bind to 0 and report back, such as the
/// SOCKS and reverse-proxy ones; parallel tests then do not fight over a fixed number.
public func freeLoopbackPort() throws -> Int {
    try LoopbackListener().port
}
