import Observation
import WatcherCore

/// Short feedback shown over the window and read out by VoiceOver; errors and notices with a button stay longer.
@MainActor @Observable
final class NoticeCenter {
    private(set) var notice: Notice?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private let announce: Announce

    init(sleep: @escaping Sleep, announce: @escaping Announce) {
        self.sleep = sleep
        self.announce = announce
    }

    func notify(_ message: String, _ kind: Notice.Kind = .info, action: NoticeAction? = nil) {
        nextID += 1
        let notice = Notice(id: nextID, message: message, kind: kind, action: action)
        self.notice = notice
        announce(message)
        dismissal?.cancel()
        let sleep = sleep
        dismissal = Task { [weak self] in
            try? await sleep(Self.lifetime(of: notice))
            guard !Task.isCancelled, let self, self.notice == notice else { return }
            self.notice = nil
        }
    }

    func dismiss() {
        dismissal?.cancel()
        notice = nil
    }

    private static func lifetime(of notice: Notice) -> Duration {
        if notice.kind == .error {
            return .seconds(9)
        }
        return notice.action == nil ? .seconds(3) : .seconds(8)
    }
}
