import SwiftUI
import WatcherCore

/// First-run setup: the three things Watcher needs before traffic shows up, each with its current state.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                WatcherLogo(size: 88)
                Text("Welcome to Watcher").font(.system(size: 24, weight: .bold))
                Text("See every request your apps make. Three quick steps and traffic starts appearing.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding(.top, 28).padding(.horizontal, 32).padding(.bottom, 20)

            VStack(spacing: 10) {
                SetupStep(
                    number: 1,
                    symbol: "lock.shield",
                    title: "Trust the certificate",
                    done: model.devices.macTrusted,
                    detail: "Lets Watcher show HTTPS in readable form. macOS asks for your password once."
                ) {
                    if model.devices.macTrusted {
                        Label("Trusted", systemImage: "checkmark").font(.callout.weight(.medium)).foregroundStyle(Palette.done)
                    } else {
                        Button("Install & Trust…") { Task { await model.devices.trustOnMac() } }
                    }
                }
                SetupStep(
                    number: 2,
                    symbol: "network",
                    title: "Capture this Mac",
                    done: model.settings.autoSystemProxy,
                    detail: "Points macOS at Watcher while it runs and restores your settings when it quits."
                ) {
                    Toggle("Capture automatically", isOn: $model.settings.autoSystemProxy).toggleStyle(.switch).labelsHidden()
                }
                SetupStep(
                    number: 3,
                    symbol: "iphone.gen3",
                    title: "Phones and other devices",
                    done: model.settings.listenOnAllInterfaces,
                    detail: "Optional. Lets devices on your Wi-Fi connect; macOS asks about Local Network the first time."
                ) {
                    Toggle("Allow devices", isOn: $model.settings.listenOnAllInterfaces).toggleStyle(.switch).labelsHidden()
                }
                DeviceStatusLabel().frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)

            HStack {
                Button("Skip for Now") { model.onboardingDone = true; model.sheet = nil }
                    .buttonStyle(.link).help("Close without starting; Help ▸ Getting Started brings this back")
                Spacer()
                Button("Set Up a Device…") { model.onboardingDone = true; model.sheet = .devices }
                Button("Start Capturing") { model.finishOnboarding() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 580)
        .task { await model.devices.refreshMacTrust() }
    }
}

/// One numbered step on a card: what it is, why, and the control that does it; a check replaces the number once done.
private struct SetupStep<Control: View>: View {
    let number: Int, symbol: String, title: String, done: Bool, detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(done ? Palette.done.opacity(0.18) : Color.accentColor.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: done ? "checkmark" : symbol).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(done ? Palette.done : Color.accentColor)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)").font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number): \(title)\(done ? ", done" : "")")
    }
}
