import AppKit
import SwiftUI

/// Menu bar presence: a status item that opens the library, plus the usual chores.
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.on.square.dashed",
                                   accessibilityDescription: "Stash")
            button.image?.isTemplate = true
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let library = menu.addItem(withTitle: "Open Library", action: #selector(openLibrary),
                                   keyEquivalent: "")
        library.tag = 903
        let search = menu.addItem(withTitle: "Quick Search", action: #selector(openSearch),
                                  keyEquivalent: "")
        search.tag = 904
        let notchItem = menu.addItem(withTitle: "Show Notch Shell", action: #selector(openNotch),
                                     keyEquivalent: "")
        notchItem.tag = 902
        applyShortcuts(to: menu)
        menu.addItem(.separator())

        let recents = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recents.tag = 900
        menu.addItem(recents)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
        pause.tag = 901
        menu.addItem(pause)
        menu.addItem(withTitle: "How Stash Works…", action: #selector(openTutorial), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        return menu
    }

    /// Mirrors the user's bindings onto the menu, so the menu never lies about
    /// which keys actually work.
    private func applyShortcuts(to menu: NSMenu) {
        let pairs: [(Int, ShortcutID)] = [(903, .library), (904, .quickSearch), (902, .notch)]
        for (tag, id) in pairs {
            guard let item = menu.item(withTag: tag) else { continue }
            if let combo = Shortcuts.shared.combo(id) {
                item.keyEquivalent = combo.menuKeyEquivalent
                item.keyEquivalentModifierMask = combo.nsModifiers
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
    }

    @objc private func openLibrary() { LibraryWindowController.shared.show() }
    @objc private func openSearch() { QuickSearchController.shared.show() }
    @objc private func openNotch() { NotchController.shared.toggleFromShortcut() }
    @objc private func openTutorial() { OnboardingWindowController.shared.show() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func togglePause() { Settings.shared.captureEnabled.toggle() }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = ClipStore.shared.items.first(where: { $0.id == id }) else { return }
        Paster.paste(item)
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        Paster.rememberFrontmostApp()

        applyShortcuts(to: menu)
        if let pause = menu.item(withTag: 901) {
            pause.title = Settings.shared.captureEnabled ? "Pause Capture" : "Resume Capture"
            pause.state = Settings.shared.captureEnabled ? .off : .on
        }

        guard let recentItem = menu.item(withTag: 900) else { return }
        let submenu = NSMenu()
        let recents = ClipStore.shared.recent(12)
        if recents.isEmpty {
            submenu.addItem(withTitle: "Nothing yet", action: nil, keyEquivalent: "")
        }
        for item in recents {
            let mi = NSMenuItem(title: item.title.isEmpty ? item.kind.title : item.title.truncated(48),
                                action: #selector(pasteRecent(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = item.id
            if let thumb = item.thumbnail {
                let copy = thumb.copy() as! NSImage
                copy.size = NSSize(width: 18, height: 18)
                mi.image = copy
            } else {
                mi.image = NSImage(systemSymbolName: item.kind.symbol, accessibilityDescription: nil)
            }
            submenu.addItem(mi)
        }
        recentItem.submenu = submenu
    }
}
