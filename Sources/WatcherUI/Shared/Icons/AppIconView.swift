import SwiftUI
import WatcherCore

/// What sent a request: the app's icon, or a symbol for tools, system services and devices.
struct AppIconView: View {
    @Environment(IconStore.self) private var icons
    let name: String
    var kind: ClientKind?
    var bundlePath: String?
    var size: CGFloat = 16

    var body: some View {
        switch icons.icon(forApp: name, kind: kind, bundlePath: bundlePath) {
        case let .image(icon):
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: size, height: size).accessibilityHidden(true)
        case let .symbol(symbol):
            Image(systemName: symbol).imageScale(.small).foregroundStyle(.secondary)
                .frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
