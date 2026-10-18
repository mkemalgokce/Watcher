extension Preferences {
    /// Set once the first-run setup has been completed or skipped.
    var onboardingDone: Bool {
        get { object(forKey: "onboarding.done") as? Bool ?? false }
        set { set(newValue, forKey: "onboarding.done") }
    }

    /// Website icons are fetched from the sites themselves; people who do not want that can switch it off in Settings.
    var websiteIconsEnabled: Bool {
        get { object(forKey: "icons.websites") as? Bool ?? true }
        set { set(newValue, forKey: "icons.websites") }
    }
}
