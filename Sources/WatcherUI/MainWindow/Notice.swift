/// One piece of feedback shown over the window.
struct Notice: Identifiable, Equatable {
    enum Kind { case success, info, error }

    let id: Int
    let message: String
    let kind: Kind
    var action: NoticeAction?

    static func == (lhs: Notice, rhs: Notice) -> Bool {
        lhs.id == rhs.id
    }
}
