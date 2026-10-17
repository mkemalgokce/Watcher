import Foundation
import WatcherCore

public extension ResponseRecord {
    static func fixture(status: Int = 200, headers: [Header] = [], body: Data = Data()) -> ResponseRecord {
        ResponseRecord(status: status, headers: headers, body: body)
    }
}
