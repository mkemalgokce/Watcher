import Observation
import WatcherCore

/// The requests and responses held at a breakpoint, and the ways to let them go.
@MainActor @Observable
final class BreakpointsViewModel {
    /// Settable inside the module so previews can show paused traffic.
    var hits: [BreakpointCenter.Hit] = []
    @ObservationIgnored private let center: BreakpointCenter
    @ObservationIgnored private let settings: SettingsEditor
    @ObservationIgnored private let notices: NoticeCenter

    init(center: BreakpointCenter, settings: SettingsEditor, notices: NoticeCenter) {
        self.center = center; self.settings = settings; self.notices = notices
    }

    func observe() {
        let changes = center.changes()
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                changed(center.pending)
            }
        }
    }

    /// New pauses are announced, never pushed into a window: opening Breakpoints on every hit took over the screen
    /// again right after an abort. The toolbar badge and status bar stay as the way in.
    func changed(_ pending: [BreakpointCenter.Hit]) {
        let added = pending.count - hits.count
        hits = pending
        if added > 0 {
            notices.notify("\(pending.count) paused at a breakpoint. Review with ⌘B, or remove the breakpoint there.")
        }
    }

    /// The breakpoint rules that stop this request.
    func rules(matching request: RequestRecord) -> [BreakpointRule] {
        settings.breakpoints.rules.filter { $0.isEnabled && RequestMatcher($0.matching).matches(request) }
    }

    /// Deletes the rules that stop `hit`'s request and lets it, and everything else they paused, continue.
    func removeBreakpoints(for hit: BreakpointCenter.Hit) {
        let doomed = rules(matching: hit.request)
        guard !doomed.isEmpty else { return proceed(hit) }
        settings.breakpoints.rules.removeAll { rule in
            doomed.contains { $0.matching == rule.matching && $0.name == rule.name }
        }
        // Whatever no remaining rule would stop is let through, so removing a breakpoint never leaves requests hanging.
        for paused in hits where rules(matching: paused.request).isEmpty {
            proceed(paused)
        }
        let removed = doomed.count == 1
            ? "Breakpoint “\(doomed[0].displayName)” removed"
            : "\(doomed.count) breakpoints removed"
        notices.notify(removed, .success)
    }

    func resolve(_ hit: BreakpointCenter.Hit, with resolution: BreakpointCenter.Resolution) {
        center.resolve(hit.id, with: resolution)
    }

    func continueAll() {
        center.releaseAll()
        notices.notify("All paused traffic continued", .success)
    }

    func abortAll() {
        center.abortAll()
        notices.notify("All paused traffic aborted")
    }

    private func proceed(_ hit: BreakpointCenter.Hit) {
        resolve(hit, with: .proceed(request: hit.request, response: hit.response))
    }
}
