/// The origin every request on a tunnelled connection (CONNECT or SOCKS) belongs to.
struct TunnelTarget: Sendable {
    let scheme: String
    let host: String
    let port: Int
}
