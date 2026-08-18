import Foundation
import AppKit
import Carbon.HIToolbox

/// A recorded keyboard shortcut. Stored as the raw key code plus AppKit modifier
/// flags, and translated to Carbon's vocabulary when registering the hot key.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, already masked to the device-independent set.
    var modifierFlags: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    var nsModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
    }

    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if nsModifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if nsModifiers.contains(.shift)   { mask |= UInt32(shiftKey) }
        if nsModifiers.contains(.option)  { mask |= UInt32(optionKey) }
        if nsModifiers.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// Function keys are usable on their own; letters and digits are not.
    var isUsable: Bool {
        if KeyNames.isFunctionKey(keyCode) { return true }
        return nsModifiers.contains(.command) || nsModifiers.contains(.control)
            || nsModifiers.contains(.option)
    }

    var displayString: String {
        KeyCombo.modifierString(nsModifiers) + KeyNames.name(for: keyCode)
    }

    /// Just the modifier glyphs, in the order macOS shows them.
    static func modifierString(_ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s
    }

    /// The character used for `NSMenuItem.keyEquivalent`.
    var menuKeyEquivalent: String {
        KeyNames.name(for: keyCode).lowercased()
    }
}

/// Turns key codes into the glyphs people expect to see, honouring the current
/// keyboard layout rather than assuming US QWERTY.
enum KeyNames {
    private static let special: [UInt16: String] = [
        UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
    ]

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        (special[keyCode]?.hasPrefix("F") ?? false) && keyCode != UInt16(kVK_ANSI_F)
    }

    static func name(for keyCode: UInt16) -> String {
        if let known = special[keyCode] { return known }
        if let ch = translate(keyCode), !ch.isEmpty { return ch.uppercased() }
        return "Key \(keyCode)"
    }

    /// Asks the active keyboard layout what this key produces unmodified.
    private static func translate(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(-1)
            }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
