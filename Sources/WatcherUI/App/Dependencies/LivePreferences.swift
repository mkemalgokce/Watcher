import Foundation

extension UserDefaults: Preferences {}

enum LivePreferences {
    /// The app's defaults domain.
    static var standard: any Preferences {
        UserDefaults.standard
    }
}
