import Foundation

extension UserDefaults: Preferences {}

enum LivePreferences {
    /// The app's defaults domain, which the views' `@AppStorage` reads too.
    static var standard: any Preferences {
        UserDefaults.standard
    }
}
