import Foundation
import AppKit
import ApplicationServices

enum Permissions {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    private static var didPrompt = false

    /// Shows the system prompt once per launch; repeat nagging is worse than useless.
    static func promptForAccessibilityOnce() {
        guard !didPrompt else { return }
        didPrompt = true
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
