import SwiftUI

extension ProxyController {
    /// For the System Proxy toggles: shows where the setting is heading, so a second click flips it back.
    var systemProxyBinding: Binding<Bool> {
        Binding(get: { self.systemProxyTarget }, set: { self.setSystemProxy($0) })
    }
}
