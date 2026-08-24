import Foundation
import AppKit
import Combine
import ServiceManagement

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var captureEnabled: Bool { didSet { d.set(captureEnabled, forKey: "captureEnabled") } }
    @Published var captureScreenshots: Bool { didSet { d.set(captureScreenshots, forKey: "captureScreenshots") } }
    @Published var notchEnabled: Bool {
        didSet {
            d.set(notchEnabled, forKey: "notchEnabled")
            NotificationCenter.default.post(name: .stashNotchPreferenceChanged, object: nil)
        }
    }
    /// The file shelf: catch files dragged to the top of the screen and hold them.
    @Published var shelfEnabled: Bool { didSet { d.set(shelfEnabled, forKey: "shelfEnabled") } }
    /// When off, the shell only opens from its shortcut or the menu bar.
    @Published var notchOpensOnHover: Bool {
        didSet {
            d.set(notchOpensOnHover, forKey: "notchOpensOnHover")
            NotchController.shared.collapse()
        }
    }
    @Published var pasteDirectly: Bool { didSet { d.set(pasteDirectly, forKey: "pasteDirectly") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }
    @Published var retentionDays: Int { didSet { d.set(retentionDays, forKey: "retentionDays") } }
    /// Bundle IDs never recorded from — password managers and the like.
    @Published var ignoredApps: [String] { didSet { d.set(ignoredApps, forKey: "ignoredApps") } }
    @Published var launchAtLogin: Bool {
        didSet {
            d.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin()
        }
    }

    static let defaultIgnoredApps = [
        "com.agilebits.onepassword7", "com.1password.1password", "com.agilebits.onepassword",
        "com.apple.keychainaccess", "com.bitwarden.desktop", "com.dashlane.Dashlane",
        "in.sinew.Enpass-Desktop", "com.lastpass.LastPass"
    ]

    private static func bool(_ d: UserDefaults, _ k: String, _ def: Bool) -> Bool {
        d.object(forKey: k) as? Bool ?? def
    }

    private init() {
        let d = UserDefaults.standard
        func bool(_ k: String, _ def: Bool) -> Bool { Settings.bool(d, k, def) }
        captureEnabled = bool("captureEnabled", true)
        captureScreenshots = bool("captureScreenshots", true)
        notchEnabled = bool("notchEnabled", true)
        notchOpensOnHover = bool("notchOpensOnHover", true)
        shelfEnabled = bool("shelfEnabled", true)
        pasteDirectly = bool("pasteDirectly", true)
        playSound = bool("playSound", false)
        retentionDays = d.object(forKey: "retentionDays") as? Int ?? 30
        ignoredApps = d.object(forKey: "ignoredApps") as? [String] ?? Settings.defaultIgnoredApps
        launchAtLogin = bool("launchAtLogin", false)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[Stash] launch-at-login: \(error)")
        }
    }

    func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return ignoredApps.contains(bundleID)
    }
}

extension Notification.Name {
    static let stashNotchPreferenceChanged = Notification.Name("stash.notchPreferenceChanged")
    static let stashShowQuickSearch = Notification.Name("stash.showQuickSearch")
    static let stashShowLibrary = Notification.Name("stash.showLibrary")
    static let stashDidCapture = Notification.Name("stash.didCapture")
}
