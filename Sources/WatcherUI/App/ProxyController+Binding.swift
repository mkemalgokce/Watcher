import SwiftUI

extension ProxyController {
    /// For the System Proxy toggles: shows where the setting is heading, so a second click flips it back.
    var systemProxyBinding: Binding<Bool> {
        Binding(get: { systemProxyTarget }, set: { setSystemProxy($0) })
    }
}
