import SwiftUI

/// The app's icon, or a terminal symbol for command-line tools.
struct AppIconView: View {
    @Environment(IconStore.self) private var icons
    let process: String
    var size: CGFloat = 16

    var body: some View {
        if let icon = icons.appIcon(for: process) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
        } else {
            Image(systemName: "terminal").font(.system(size: size * 0.75)).foregroundStyle(.secondary).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
