import Foundation
import WritingCore

/// Choices the person makes in the menu bar, kept in UserDefaults.
enum Settings {
    private static let setupKey = "finishedSetup"

    static var finishedSetup: Bool {
        get { UserDefaults.standard.bool(forKey: setupKey) }
        set { UserDefaults.standard.set(newValue, forKey: setupKey) }
    }

    static var blockedSites: [String] {
        get { UserDefaults.standard.stringArray(forKey: "blockedSites") ?? defaultBlockedSites }
        set { UserDefaults.standard.set(newValue, forKey: "blockedSites") }
    }

    static var blockedApps: [String] {
        get { UserDefaults.standard.stringArray(forKey: "blockedApps") ?? defaultBlockedApps }
        set { UserDefaults.standard.set(newValue, forKey: "blockedApps") }
    }
}
