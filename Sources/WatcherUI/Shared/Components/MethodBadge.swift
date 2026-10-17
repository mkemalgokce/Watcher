import SwiftUI

struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(method).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(Palette.method(method))
    }
}
