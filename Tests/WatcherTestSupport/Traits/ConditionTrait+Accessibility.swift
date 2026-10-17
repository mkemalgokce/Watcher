import Testing

public extension Trait where Self == ConditionTrait {
    /// Enables a suite only where accessibility can drive the test windows, so it reports skipped elsewhere (CI).
    static var accessibilityGranted: Self {
        .enabled(
            """
            Accessibility must be granted to the app running the tests (System Settings ▸ Privacy & Security ▸ \
            Accessibility) and must answer with the test window; if it is granted, restart Terminal or run from Xcode.
            """
        ) {
            await AccessibilityProbe.isUsable()
        }
    }
}
