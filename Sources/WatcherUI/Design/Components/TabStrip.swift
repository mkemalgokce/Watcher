import SwiftUI

/// One choice in a `TabStrip`.
struct TabItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let symbol: String
    var badge: String?
    var shortcut: String?
}

/// A row of tabs on a glass capsule: symbol and title when there is room, symbols alone when not. The selection slides.
struct TabStrip<ID: Hashable>: View {
    let items: [TabItem<ID>]
    @Binding var selection: ID
    @Namespace private var namespace

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(showsTitles: true)
            strip(showsTitles: false)
        }
    }

    private func strip(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.id == selection
                Button { withAnimation(.snappy(duration: 0.22)) { selection = item.id } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold))
                        if showsTitles {
                            Text(item.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                        }
                        if let badge = item.badge {
                            Text(badge).font(.system(size: 9, weight: .bold).monospacedDigit())
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.22), in: Capsule())
                        }
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, showsTitles ? 10 : 8).frame(height: 24)
                    .background {
                        if selected {
                            Capsule().fill(Color.accentColor.opacity(0.18))
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.shortcut.map { "\(item.title) (\($0))" } ?? item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        // A flat track rather than glass: tab titles must stay crisp over any content.
        .background(Color.secondary.opacity(0.1), in: Capsule())
        .fixedSize()
    }
}
