import SwiftUI

/// Outcome of the last device action: in progress, done, or failed.
struct DeviceStatusLabel: View {
    @Environment(DevicesViewModel.self) private var devices

    var body: some View {
        if let status = devices.status {
            HStack(spacing: 6) {
                switch status {
                case .working: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.done)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.error)
                }
                Text(status.text).textSelection(.enabled)
                    .foregroundStyle({
                        if case .failed = status {
                            Palette.error
                        } else {
                            Color.secondary
                        }
                    }())
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }
    }
}
