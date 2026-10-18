import SwiftUI

/// Stays above the list while the session records into a temporary folder.
struct StartupProblemBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let problem = model.startupProblem {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityHidden(true)
                Text(problem.message).font(.callout).textSelection(.enabled)
                Spacer()
                Button("Show Folder") { model.showStartupFolder() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.red.opacity(0.12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Error: \(problem.message)")
        }
    }
}
