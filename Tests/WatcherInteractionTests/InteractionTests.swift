import Testing
import WatcherTestSupport

/// Flows driven the way a user drives them: the screen is shown in a real window and its controls are pressed through
/// accessibility (what VoiceOver and UI automation use), then the outcome is read from the model. Every screen suite
/// nests here so `.serialized` covers them all, because they share NSApp and the process's windows.
@Suite(.serialized, .accessibilityGranted, .tags(.accessibility))
enum InteractionTests {}
