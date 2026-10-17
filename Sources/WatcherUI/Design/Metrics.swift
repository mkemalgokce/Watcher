import SwiftUI

/// Spacing, radii and type used by every redesigned screen, so panes line up with each other.
enum Metrics {
    static let gutter: CGFloat = 14
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
    static let iconButton: CGFloat = 30
}

// MARK: Glass

/// Liquid Glass on macOS 26 and later; a quiet material with a hairline edge before that.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var interactive = false
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let glass = Glass.regular.tint(tint)
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content
                .background((tint ?? .clear).opacity(0.18), in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }
}

extension View {
    func glassSurface(_ shape: some InsettableShape, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive, tint: tint))
    }
}

/// Groups glass shapes so neighbouring ones blend and morph together (a no-op before macOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: Icon buttons

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

// MARK: Tabs

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

// MARK: Content blocks

/// A titled block of related content on a quiet raised surface.
struct Card<Content: View, Accessory: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(spacing: 6) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    if let title {
                        Text(title).font(.system(size: 11, weight: .semibold)).textCase(.uppercase).foregroundStyle(.secondary).tracking(0.4)
                    }
                    Spacer(minLength: 0)
                    accessory
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

extension Card where Accessory == EmptyView {
    init(_ title: String? = nil, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: { EmptyView() }, content: content)
    }
}

/// Lays its children out left to right and starts a new line when the next one does not fit, like words in a sentence.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [], current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current); current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

/// A coloured capsule with short text, e.g. a status code or a tag.
struct Pill: View {
    let text: String
    var tint: Color = .secondary
    var monospaced = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: monospaced ? .monospaced : .default).monospacedDigit())
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
