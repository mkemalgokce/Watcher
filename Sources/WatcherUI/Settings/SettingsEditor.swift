import Observation
import WatcherCore

/// The window's editable copy of the settings. Edits are saved and applied after a short pause, so typing in a field
/// does not restart listeners on every keystroke.
@MainActor @Observable @dynamicMemberLookup
final class SettingsEditor {
    var value: WatcherSettings {
        didSet {
            scheduleCommit()
            onChange?(oldValue, value)
        }
    }

    /// Lets the window react to a change that affects more than the settings, such as hiding Apple traffic.
    @ObservationIgnored var onChange: ((_ old: WatcherSettings, _ new: WatcherSettings) -> Void)?
    @ObservationIgnored private var commit: Task<Void, Never>?
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private let notices: NoticeCenter
    @ObservationIgnored private let persist: (WatcherSettings) throws -> Void
    @ObservationIgnored private let apply: (WatcherSettings) async -> Void
    @ObservationIgnored private let suggestPort: () -> Int?

    init(
        initial: WatcherSettings,
        sleep: @escaping Sleep,
        notices: NoticeCenter,
        persist: @escaping (WatcherSettings) throws -> Void,
        apply: @escaping (WatcherSettings) async -> Void,
        suggestReversePort: (() -> Int?)? = nil
    ) {
        value = initial
        self.sleep = sleep; self.notices = notices; self.persist = persist; self.apply = apply
        suggestPort = suggestReversePort ?? { nil }
    }

    /// Edits the engine's settings, which it saves to disk and applies to the running proxy.
    convenience init(engine: WatcherEngine, sleep: @escaping Sleep, notices: NoticeCenter) {
        self.init(
            initial: engine.settings.value,
            sleep: sleep,
            notices: notices,
            persist: { [engine] in try engine.settings.replace(with: $0) },
            apply: { [engine] in await engine.apply($0) },
            suggestReversePort: { [engine] in engine.suggestReversePort() }
        )
    }

    /// A free local port for a new Reverse Proxy rule.
    func suggestReversePort() -> Int? {
        suggestPort()
    }

    subscript<Field>(dynamicMember field: KeyPath<WatcherSettings, Field>) -> Field {
        value[keyPath: field]
    }

    subscript<Field>(dynamicMember field: WritableKeyPath<WatcherSettings, Field>) -> Field {
        get { value[keyPath: field] }
        set { value[keyPath: field] = newValue }
    }

    private func scheduleCommit() {
        commit?.cancel()
        let sleep = sleep
        commit = Task {
            try? await sleep(.milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try persist(value)
                await apply(value)
            } catch { notices.notify("\(error)", .error) }
        }
    }
}
