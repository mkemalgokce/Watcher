/// A button in a notice, such as Undo; it disappears with the notice.
struct NoticeAction {
    let title: String
    let perform: @MainActor () -> Void
}
