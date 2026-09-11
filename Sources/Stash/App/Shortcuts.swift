import Foundation
import AppKit
import Carbon.HIToolbox
import Combine

/// Everything Stash can be triggered by. Each one is freely rebindable.
enum ShortcutID: String, CaseIterable, Codable, Identifiable {
    case notch
    case quickSearch
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return "Notch Shell"
        case .quickSearch: return "Quick Search"
        case .library: return "Library"
        }
    }

    var subtitle: String {
        switch self {
        case .notch: return "Opens the clip strip; press it again to close."
        case .quickSearch: return "Search everything and paste with ⏎."
        case .library: return "The full window with sidebar and inspector."
        }
    }

    var symbol: String {
        switch self {
        case .notch: return "rectangle.topthird.inset.filled"
        case .quickSearch: return "magnifyingglass"
        case .library: return "square.grid.2x2"
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .notch:
            #if APPSTORE
            // Reviewers reject apps that take over standard system shortcuts.
            return KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command, .shift])
            #else
            return KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command])
            #endif
        case .quickSearch: return KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift])
        case .library:     return KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command, .shift])
        }
    }
}

/// Owns the bindings, persists them, and keeps the registered hot keys in sync.
final class Shortcuts: ObservableObject {
    static let shared = Shortcuts()

    /// A missing entry means "no shortcut" — the action is still reachable from the menu bar.
    @Published private(set) var bindings: [ShortcutID: KeyCombo] = [:]

    /// Overridden by the self-test so it never rewrites the real bindings.
    static var defaultsStore: UserDefaults = .standard
    private var d: UserDefaults { Shortcuts.defaultsStore }

    private let storageKey = "shortcutBindings"
    private var suspended = false

    private init() {
        load()
    }

    // MARK: Access

    func combo(_ id: ShortcutID) -> KeyCombo? { bindings[id] }

    /// The string to show in menus, tutorials and hints. Empty when unbound.
    func label(_ id: ShortcutID) -> String { bindings[id]?.displayString ?? "" }

    /// Same, but with a readable fallback for prose.
    func labelOrNone(_ id: ShortcutID) -> String {
        bindings[id]?.displayString ?? "not set"
    }

    // MARK: Mutation

    func set(_ combo: KeyCombo?, for id: ShortcutID) {
        if let combo { bindings[id] = combo } else { bindings.removeValue(forKey: id) }
        save()
        applyAll()
    }

    func reset(_ id: ShortcutID) { set(id.defaultCombo, for: id) }

    func resetAll() {
        bindings = Dictionary(uniqueKeysWithValues: ShortcutID.allCases.map { ($0, $0.defaultCombo) })
        save()
        applyAll()
    }

    // MARK: Conflicts

    /// Another Stash action already using this combo.
    func conflict(with combo: KeyCombo, excluding id: ShortcutID) -> ShortcutID? {
        bindings.first { $0.key != id && $0.value == combo }?.key
    }

    /// Well-known system or app shortcuts this would shadow. Advisory only —
    /// the user is allowed to pick them anyway.
    func systemWarning(for combo: KeyCombo) -> String? {
        let mods = combo.nsModifiers
        guard mods == [.command] else { return nil }
        let shadowed: [UInt16: String] = [
            UInt16(kVK_ANSI_C): "Copy", UInt16(kVK_ANSI_V): "Paste", UInt16(kVK_ANSI_X): "Cut",
            UInt16(kVK_ANSI_P): "Print", UInt16(kVK_ANSI_S): "Save", UInt16(kVK_ANSI_Z): "Undo",
            UInt16(kVK_ANSI_A): "Select All", UInt16(kVK_ANSI_W): "Close Window",
            UInt16(kVK_ANSI_Q): "Quit", UInt16(kVK_ANSI_N): "New", UInt16(kVK_ANSI_O): "Open",
            UInt16(kVK_ANSI_F): "Find", UInt16(kVK_ANSI_T): "New Tab",
            UInt16(kVK_Space): "Spotlight"
        ]
        guard let name = shadowed[combo.keyCode] else { return nil }
        return "Takes \(name) (\(combo.displayString)) away from every other app while Stash runs."
    }

    // MARK: Registration

    /// Silences every hot key — used while recording so the combo being pressed
    /// does not trigger the very action being rebound.
    func suspend() {
        suspended = true
        for id in ShortcutID.allCases { HotKeyCenter.shared.unregister(id.rawValue) }
    }

    func resume() {
        suspended = false
        applyAll()
    }

    func applyAll() {
        guard !suspended else { return }
        for id in ShortcutID.allCases {
            HotKeyCenter.shared.unregister(id.rawValue)
            guard let combo = bindings[id] else { continue }
            HotKeyCenter.shared.register(id.rawValue,
                                         keyCode: UInt32(combo.keyCode),
                                         modifiers: combo.carbonModifiers) {
                Shortcuts.perform(id)
            }
        }
        NotificationCenter.default.post(name: .stashShortcutsChanged, object: nil)
    }

    private static func perform(_ id: ShortcutID) {
        switch id {
        case .notch: NotchController.shared.toggleFromShortcut()
        case .quickSearch: QuickSearchController.shared.toggle()
        case .library: LibraryWindowController.shared.toggle()
        }
    }

    // MARK: Persistence

    /// Cleared shortcuts have to be recorded explicitly, otherwise the defaults
    /// would quietly come back on the next launch.
    private struct Stored: Codable {
        var bindings: [String: KeyCombo] = [:]
        var cleared: [String] = []
    }

    private func load() {
        let defaults = d
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            bindings = Dictionary(uniqueKeysWithValues: ShortcutID.allCases.map { ($0, $0.defaultCombo) })
            // Carry over the old boolean that used to pick ⌘P vs ⌘⇧P.
            if defaults.object(forKey: "notchShortcutIsCommandP") as? Bool == false {
                bindings[.notch] = KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command, .shift])
            }
            save()
            return
        }

        let cleared = Set(stored.cleared)
        for id in ShortcutID.allCases {
            if let combo = stored.bindings[id.rawValue] {
                bindings[id] = combo
            } else if !cleared.contains(id.rawValue) {
                bindings[id] = id.defaultCombo   // a shortcut added in a later version
            }
        }
    }

    private func save() {
        var stored = Stored()
        for (id, combo) in bindings { stored.bindings[id.rawValue] = combo }
        stored.cleared = ShortcutID.allCases.map(\.rawValue).filter { bindings[ShortcutID(rawValue: $0)!] == nil }
        if let data = try? JSONEncoder().encode(stored) {
            d.set(data, forKey: storageKey)
        }
    }
}

extension Notification.Name {
    static let stashShortcutsChanged = Notification.Name("stash.shortcutsChanged")
}
