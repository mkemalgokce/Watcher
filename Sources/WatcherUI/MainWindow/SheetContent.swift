import SwiftUI

/// The screen each sheet shows; the one place a new `WindowRouter.Sheet` case has to be given a view.
struct SheetContent: View {
    @Environment(AppModel.self) private var model
    let sheet: WindowRouter.Sheet

    var body: some View {
        switch sheet {
        case .tools: ToolsView()
        case .breakpoints: BreakpointsView()
        case .compose: ComposeView(now: model.now)
        case .devices: DeviceSetupView()
        case .welcome: WelcomeView()
        case .converter: ConverterView()
        case .help: HelpView()
        }
    }
}
