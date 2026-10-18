import AppKit
import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// Every scene and sheet is hosted once with the app model, so a view that reads an environment object the model does
/// not provide crashes here instead of at the first launch. ContentView itself is hosted as its three columns, the
/// status bar and the notices: laid out whole in a bare hosting view, SwiftUI builds the sidebar's table rows without the
/// environment and traps, which a Window scene never does.
@MainActor
@Suite(.timeLimit(.minutes(1)), .serialized, .tags(.smoke, .integration, .ui))
struct ScreenSmokeTests {
    private static let size = CGSize(width: 900, height: 640)

    private static let screens: [(String, @MainActor (AppModel) -> AnyView)] = [
        ("sidebar", { model in AnyView(SidebarView().environment(model)) }),
        ("flow list", { model in AnyView(FlowListView().environment(model)) }),
        ("inspector", { model in AnyView(FlowDetailView().environment(model)) }),
        ("status bar", { model in AnyView(StatusBar(viewModel: model.statusBar).environment(model)) }),
        ("notices", { model in AnyView(NoticeBanner().environment(model)) }),
        ("tools", { model in AnyView(ToolsView().environment(model)) }),
        ("breakpoints", { model in AnyView(BreakpointsView().environment(model)) }),
        ("compose", { model in AnyView(ComposeView(now: model.now).environment(model)) }),
        ("devices", { model in AnyView(DeviceSetupView().environment(model)) }),
        ("welcome", { model in AnyView(WelcomeView().environment(model)) }),
        ("converter", { model in AnyView(ConverterView().environment(model)) }),
        ("help", { model in AnyView(HelpView().environment(model)) }),
        ("compare", { model in AnyView(CompareWindow().environment(model)) }),
        ("about", { model in AnyView(AboutView().environment(model)) }),
        ("settings", { model in AnyView(SettingsView().environment(model)) }),
        ("menu bar menu", { model in AnyView(MenuBarMenu().environment(model)) }),
        ("menu bar label", { model in AnyView(MenuBarLabel().environment(model)) }),
    ]

    @Test(arguments: screens.map(\.0))
    func theScreenLaysOutWithTheAppModelsEnvironment(name: String) throws {
        let model = try AppModel.demo()
        let build = try #require(Self.screens.first { $0.0 == name }?.1)
        let window = NSWindow.hosting(build(model), size: Self.size)
        defer { window.close() }
        window.orderFrontRegardless()
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        #expect(content.frame.size == Self.size, "\(name) laid out")
    }

    @Test
    func everySheetTheRouterCanShowIsHostedAbove() {
        #expect(WindowRouter.Sheet.allCases.count == 7, "add the new sheet to the screens above")
    }
}
