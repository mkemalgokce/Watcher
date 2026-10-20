import SwiftUI

/// Where the inspector sits next to the request list. Below gives the list the window's full width, which is what
/// long URLs need; beside keeps the list tall.
enum InspectorLayout: String, CaseIterable, Identifiable {
    case bottom, right, hidden

    static let storageKey = "inspectorLayout"

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .bottom: "Inspector at Bottom"
        case .right: "Inspector on Right"
        case .hidden: "Hide Inspector"
        }
    }

    var symbol: String {
        switch self {
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        case .hidden: "rectangle"
        }
    }
}

/// The request list and its inspector with a draggable divider; each layout remembers its own inspector size.
struct TrafficSplit: View {
    @AppStorage(InspectorLayout.storageKey) private var layout = InspectorLayout.bottom
    @AppStorage("inspectorHeight") private var height = 380.0
    @AppStorage("inspectorWidth") private var width = 520.0

    var body: some View {
        if layout == .hidden {
            FlowListView()
        } else {
            let below = layout == .bottom
            ResizableSplit(
                axis: below ? .vertical : .horizontal, secondSize: below ? $height : $width,
                minFirst: below ? 160 : 360, minSecond: below ? 220 : 340
            ) {
                FlowListView()
            } second: {
                FlowDetailView()
            }
        }
    }
}

/// Toolbar menu for the layout; the View menu has the same choice.
struct InspectorLayoutMenu: View {
    @AppStorage(InspectorLayout.storageKey) private var layout = InspectorLayout.bottom

    var body: some View {
        Menu {
            InspectorLayoutPicker()
        } label: {
            Label("Layout", systemImage: layout.symbol)
        }
        .help("Where the inspector goes: below the list, beside it, or hidden")
    }
}

struct InspectorLayoutPicker: View {
    @AppStorage(InspectorLayout.storageKey) private var layout = InspectorLayout.bottom

    var body: some View {
        Picker("Inspector", selection: $layout) {
            ForEach(InspectorLayout.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.inline)
    }
}
