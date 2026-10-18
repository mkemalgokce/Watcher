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
    var panels: any FilePanels
    var files: FileAccess
    var commands: CommandRunner
    var preferences: any Preferences
    var runner: any ProxyRunning
    var systemProxy: any SystemProxying
    var onTerminate: OnTerminate
    var sender: any RequestSending
    var workspace: any WorkspaceOpener
    var paths: SupportPaths
    var focusFilterField: @MainActor () -> Void
    var devices: DevicesViewModel.DeviceProbe
    var loginItem: LoginItem
    var now: @Sendable () -> Date

    var requestServices: RequestActions.Services {
        RequestActions.Services(sender: sender, clipboard: clipboard, workspace: workspace, paths: paths, files: files)
    }
}
