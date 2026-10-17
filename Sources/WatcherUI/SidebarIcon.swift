import SwiftUI

/// A coloured sidebar icon that turns white on the selected row, where the accent-coloured highlight would hide it.
struct SidebarIcon: View {
    let symbol: String
    let tint: Color
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Image(systemName: symbol).foregroundStyle(prominence == .increased ? .white : tint)
    }
}
