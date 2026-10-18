import SwiftUI

/// The website's favicon, or a globe while it loads or when the site has none.
struct SiteIconView: View {
    @Environment(IconStore.self) private var icons
    let domain: String
    var size: CGFloat = 16

    var body: some View {
        if let icon = icons.favicon(for: domain) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
        } else {
            Image(systemName: "globe").font(.system(size: size * 0.8)).foregroundStyle(.secondary).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
