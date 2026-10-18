import AppKit
import WatcherCore

/// Everything the window's models reach outside the process through: the app passes `.live`, previews `.preview`
/// and tests their doubles.
@MainActor
public struct AppDependencies {
    var engine: WatcherEngine
    var clipboard: any Clipboard
    var sleep: Sleep
    var announce: Announce
}
