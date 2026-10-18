import NIO

extension Channel {
    func boundPort() throws -> Int {
        guard let port = localAddress?.port else { throw TestSupportError("the listener has no bound port") }
        return port
    }
}
