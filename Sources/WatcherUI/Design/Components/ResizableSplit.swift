import AppKit
import SwiftUI

/// Two panes with a draggable divider, on either axis, in plain SwiftUI layout. NSSplitView (HSplitView, VSplitView) rebuilt
/// its panes when the axis or content changed and lost the divider position; here the same two views keep their identity
/// when the axis flips, and the size of the second pane is a stored value.
struct ResizableSplit<First: View, Second: View>: View {
    let axis: Axis
    /// Points the second pane takes along `axis`; the first pane gets the rest.
    @Binding var secondSize: Double
    let minFirst: Double
    let minSecond: Double
    @ViewBuilder let first: First
    @ViewBuilder let second: Second
    @State private var dragStart: Double?
    @State private var isHovering = false

    private static var grip: Double {
        9
    }

    /// Keeps both panes at least their minimum; when the space is too small for both, the first pane wins.
    static func clamped(_ size: Double, total: Double, minFirst: Double, minSecond: Double) -> Double {
        min(max(size, minSecond), max(0, total - minFirst - 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontal = axis == .horizontal
            let total = horizontal ? geometry.size.width : geometry.size.height
            let size = Self.clamped(secondSize, total: total, minFirst: minFirst, minSecond: minSecond)
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                first.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                    .overlay { grip(total: total, size: size, horizontal: horizontal) }
                second
                    .frame(width: horizontal ? size : nil, height: horizontal ? nil : size)
                    .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
            }
        }
    }

    /// A wider invisible target than the 1 pt line, with the resize cursor and VoiceOver adjustment.
    private func grip(total: Double, size: Double, horizontal: Bool) -> some View {
        Color.clear
            .frame(width: horizontal ? Self.grip : nil, height: horizontal ? nil : Self.grip)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != isHovering else { return }
                isHovering = inside
                if inside {
                    (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            // A layout change can remove the divider under the pointer; without this the resize cursor would stay.
            .onDisappear {
                if isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? size
                        dragStart = start
                        let moved = horizontal ? drag.translation.width : drag.translation.height
                        // The divider moves with the pointer, so the second pane shrinks as it moves down or right.
                        secondSize = Self.clamped(start - moved, total: total, minFirst: minFirst, minSecond: minSecond)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("Divider")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? -40.0 : 40.0
                secondSize = Self.clamped(size + step, total: total, minFirst: minFirst, minSecond: minSecond)
            }
    }
}
