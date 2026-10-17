import Foundation

public enum RequestDecision: Sendable {
    case forward
    case respond(ResponseRecord)
    /// `hidden` keeps the blocked request out of the session list.
    case block(hidden: Bool)
}
