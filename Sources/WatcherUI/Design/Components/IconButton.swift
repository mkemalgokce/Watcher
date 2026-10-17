import SwiftUI

/// A small symbol button. The tooltip always says what it does and its shortcut; hovering lifts it onto glass
/// so it is obvious it can be clicked. VoiceOver reads the title.
struct IconButton: View {
    let title: String
    let symbol: String
    var shortcut: String?
    var tint: Color?
    var isOn = false
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, symbol: String, shortcut: String? = nil, tint: Color? = nil, isOn: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.shortcut = shortcut; self.tint = tint; self.isOn = isOn; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .symbolVariant(isOn ? .fill : .none)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint ?? (hovering || isOn ? Color.primary : Color.secondary))
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if hovering || isOn {
                Color.clear.glassSurface(Circle(), interactive: true)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
