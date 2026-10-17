import AppKit
import SwiftUI

/// The app's own icon inside its windows; follows the Dock icon, including its light, dark and tinted looks.
struct WatcherLogo: View {
    var size: CGFloat = 56

    var body: some View {
        // The packaged app's icon is the system's (Liquid Glass on macOS 26); unbundled runs (swift run, Xcode, tests) would show
        // their host's, so they read Watcher's own icns instead.
        let image = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil ? NSApp.applicationIconImage : WatcherAppIcon.image ?? NSApp.applicationIconImage
        Image(nsImage: image ?? NSImage()).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
    }
}
