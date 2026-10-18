/// The "keep at most" stepper's label: 0 means no limit.
enum FlowLimitText {
    static func label(for limit: Int) -> String {
        "Keep at most \(limit == 0 ? "∞" : String(limit)) requests"
    }
}
