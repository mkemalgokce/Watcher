import Observation
import WatcherCore

/// Which dialog, page and half of the exchange the windows show, and requests to move focus or bring Compare forward.
@MainActor @Observable
final class WindowRouter {
    enum Sheet: Identifiable {
        case tools, breakpoints, compose, devices, welcome, converter, help
        var id: Self {
            self
        }
    }

    /// The dialog currently shown over the main window; menus and toolbar both open it through here.
    var sheet: Sheet?
    /// The page Tools opens on; callers set it to land on the tool they mean.
    var toolsSelection = ToolsView.Tool.sslProxying
    /// The half of the exchange shown when the inspector is too narrow for both side by side.
    var exchangeSide = MessageSide.response
    var askWorkspaceName = false
    /// Request to pre-fill the compose window with (Edit & Repeat, New Request from cURL).
    var composeDraft: RequestRecord?
    /// The captured flow an Edit & Repeat started from, so Compose can show what changed and compare the answers.
    var composeSource: Flow?
    /// Hide WebSocket ping/pong control frames in the message list.
    var hidePingPong = true
    /// Flow that the Compare window holds the selection against.
    var diffBase: Flow?
    /// Bumped to move keyboard focus into the request filter field (⌘F outside a body).
    private(set) var searchFocusRequest = 0
    /// Bumped to bring the Compare window forward; the main window turns it into openWindow, which only views can call.
    private(set) var compareWindowRequest = 0

    @ObservationIgnored private let notices: NoticeCenter
    @ObservationIgnored private let focusFilterField: @MainActor () -> Void

    init(notices: NoticeCenter, focusFilterField: @escaping @MainActor () -> Void) {
        self.notices = notices
        self.focusFilterField = focusFilterField
    }

    func show(_ sheet: Sheet) {
        self.sheet = sheet
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
        focusFilterField()
    }

    /// Opens Compose filled with `request`; `source` is the captured flow it came from, if any.
    func compose(_ request: RequestRecord, from source: Flow?) {
        composeDraft = request
        composeSource = source
        sheet = .compose
    }

    /// Remembers `flow` as the base and opens Compare, which then follows whatever is selected in the list.
    func compare(withBase flow: Flow) {
        diffBase = flow
        compareWindowRequest += 1
        notices.notify("#\(flow.sequence) is the compare base. Select another request to compare.")
    }
}
