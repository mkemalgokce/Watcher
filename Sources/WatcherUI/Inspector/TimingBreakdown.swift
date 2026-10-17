import Foundation
import WatcherCore

/// Where the time of one exchange went, for the inspector header.
struct TimingBreakdown: Equatable {
    struct Phase: Equatable, Identifiable {
        enum Kind: Equatable { case waiting, receiving }
        var id: Kind {
            kind
        }

        let kind: Kind
        let title: String
        let detail: String
        let seconds: TimeInterval
        /// Share of the total, 0...1.
        let fraction: Double
    }

    let total: TimeInterval
    let phases: [Phase]
    let isComplete: Bool

    init(_ flow: Flow) {
        let total = max(0, flow.duration ?? 0)
        self.total = total
        isComplete = flow.duration != nil && flow.state != .pending
        // Clamped: a first byte reported after the end (clock skew, a failed transfer) must not produce a negative phase.
        let waiting = min(total, max(0, flow.timeToFirstByte ?? total))
        let receiving = max(0, total - waiting)
        func share(_ value: TimeInterval) -> Double {
            total > 0 ? value / total : 0
        }
        phases = [
            Phase(kind: .waiting, title: "Waiting for the server", detail: "From sending the request until the first byte came back.", seconds: waiting, fraction: share(waiting)),
            Phase(kind: .receiving, title: "Receiving the response", detail: "Downloading the rest of the body.", seconds: receiving, fraction: share(receiving)),
        ]
    }

    /// One sentence a developer can act on.
    var verdict: String {
        guard isComplete, total > 0 else { return "The response has not finished yet." }
        let waiting = phases[0]
        if total < 0.1 {
            return "Fast: answered in \(Format.duration(total))."
        }
        if waiting.fraction >= 0.8 {
            return "The server spent \(Int((waiting.fraction * 100).rounded()))% of the time before answering. Look at server-side work."
        }
        if waiting.fraction <= 0.3 {
            return "Most of the time went into downloading the body. A smaller or compressed response would help."
        }
        return "Time is split between the server and the download."
    }
}
