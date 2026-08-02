import Foundation

/// UserDefaults keys for app behaviour. Add new optional tabs / features here as you expose them in Settings.
enum AppPreferences {
    enum Keys {
        /// When `false`, the Jobs tab is omitted from the tab bar, and job-related UI elsewhere is hidden.
        static let showJobsTab = "preferences.showJobsTab"
    }
}
