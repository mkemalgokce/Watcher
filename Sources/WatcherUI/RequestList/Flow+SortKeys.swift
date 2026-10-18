import Foundation
import WatcherCore

/// Values the list sorts by: plain Comparable stand-ins for the optional parts of a flow.
extension Flow {
    /// No response sorts first, failures before any status code.
    var sortStatus: Int {
        state == .failed ? -1 : response?.status ?? 0
    }

    var sortURL: String {
        request.url
    }

    var sortSize: Int {
        response?.body.count ?? -1
    }

    /// Unfinished requests sort as the longest, so they stand out at the end of a duration sort.
    var sortDuration: TimeInterval {
        duration ?? .greatestFiniteMagnitude
    }

    var sortApp: String {
        request.clientApp ?? ""
    }
}
