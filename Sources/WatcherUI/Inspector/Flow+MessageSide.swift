import Foundation
import WatcherCore

extension Flow {
    /// The headers of one half of the exchange; none while there is no response.
    func headers(_ side: MessageSide) -> [Header] {
        side == .request ? request.headers : response?.headers ?? []
    }

    /// The body as captured (still Content-Encoded) of one half of the exchange.
    func body(_ side: MessageSide) -> Data {
        side == .request ? request.body : response?.body ?? Data()
    }
}
