import SwiftUI

public extension View {
    /// Puts the app model and every view model it built into the environment. It overloads SwiftUI's
    /// `environment(_:)` so that no window can be given the app model without the view models its views read.
    func environment(_ model: AppModel) -> some View {
        environment(Optional(model))
            .environment(model.router)
            .environment(model.list)
            .environment(model.proxy)
            .environment(model.notices)
            .environment(model.breakpoints)
            .environment(model.actions)
            .environment(model.externalApps)
            .environment(model.sessionFiles)
            .environment(model.workspaces)
            .environment(model.devices)
            .environment(model.settings)
    }
}
