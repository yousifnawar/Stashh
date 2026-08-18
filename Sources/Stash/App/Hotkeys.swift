import Foundation
import AppKit
import Carbon.HIToolbox

/// Carbon hot keys — the only way to get a true system-wide shortcut without
/// asking for Accessibility permission up front.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Entry {
        var ref: EventHotKeyRef?
        var handler: () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var idsByName: [String: UInt32] = [:]
    private var installed = false
    private var nextID: UInt32 = 1

    private init() {}

    /// Registering the same name twice replaces the previous binding.
    func register(_ name: String, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister(name)
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53545348), id: id) // 'STSH'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            NSLog("[Stash] hotkey '\(name)' failed to register: \(status)")
            return
        }
        entries[id] = Entry(ref: ref, handler: handler)
        idsByName[name] = id
    }

    func unregister(_ name: String) {
        guard let id = idsByName.removeValue(forKey: name), let entry = entries.removeValue(forKey: id)
        else { return }
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
    }

    fileprivate func fire(_ id: UInt32) { entries[id]?.handler() }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async { HotKeyCenter.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum HotKeys {
    /// Registers whatever the user has bound. Called once at launch; Shortcuts
    /// re-applies on every change after that.
    static func installDefaults() {
        Shortcuts.shared.applyAll()
    }
}
