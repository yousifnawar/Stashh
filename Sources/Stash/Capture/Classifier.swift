import Foundation
import AppKit

/// Turns raw pasteboard payloads into a typed, titled, searchable ClipItem.
enum Classifier {

    private static let codeHints: [String] = [
        "func ", "def ", "class ", "import ", "#include", "const ", "let ", "var ",
        "public ", "private ", "return ", "=>", "{\n", "};", "</", "/>", "SELECT ",
        "npm ", "git ", "sudo ", "->", "::", "&&", "||", "print(", "console.log"
    ]

    static func kindForText(_ text: String) -> ItemKind {
        let t = text.trimmed
        if isColor(t) { return .color }
        if isLink(t) { return .link }
        if isCode(t) { return .code }
        return .text
    }

    static func isLink(_ t: String) -> Bool {
        guard !t.isEmpty, !t.contains(" "), t.count < 2048 else { return false }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return URL(string: t) != nil }
        // Bare domains like example.com/path
        let pattern = #"^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(/\S*)?$"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    static func isColor(_ t: String) -> Bool {
        let hex = #"^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
        if t.range(of: hex, options: .regularExpression) != nil { return true }
        let fn = #"^(rgb|rgba|hsl|hsla)\(\s*[\d.%\s,/]+\)$"#
        return t.range(of: fn, options: .regularExpression) != nil
    }

    static func isCode(_ t: String) -> Bool {
        guard t.count > 12 else { return false }
        let lines = t.split(separator: "\n")
        var hits = codeHints.filter { t.contains($0) }.count
        // Leading indentation across several lines is a strong signal.
        let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        if lines.count > 2 && indented >= max(1, lines.count / 3) { hits += 1 }
        if t.contains(";\n") { hits += 1 }
        return hits >= 2
    }

    static func colorHex(from t: String) -> String? {
        let trimmed = t.trimmed
        if let c = NSColor(hex: trimmed) { return c.hexString }
        // rgb()/rgba() → hex
        let nums = trimmed.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap { Double($0) }
        if trimmed.lowercased().hasPrefix("rgb"), nums.count >= 3 {
            return String(format: "#%02X%02X%02X", Int(nums[0]), Int(nums[1]), Int(nums[2]))
        }
        return nil
    }

    /// A short label for the card header.
    static func title(for kind: ItemKind, text: String, fileURLs: [String]) -> String {
        switch kind {
        case .link:
            if let url = URL(string: text.trimmed), let host = url.host {
                let path = url.path.isEmpty || url.path == "/" ? "" : url.path
                return (host + path).truncated(70)
            }
            return text.firstLine.truncated(70)
        case .color:
            return colorHex(from: text) ?? text.trimmed
        case .file:
            if fileURLs.count == 1 { return (fileURLs[0] as NSString).lastPathComponent }
            return "\(fileURLs.count) files"
        case .code:
            return text.firstLine.truncated(70)
        default:
            return text.firstLine.truncated(70)
        }
    }

    /// Screenshots come from macOS's own capture UI, or land in the screenshot folder.
    static func isScreenshotSource(bundleID: String?) -> Bool {
        guard let b = bundleID else { return false }
        return b == "com.apple.screencaptureui" || b == "com.apple.screenshot.launcher"
    }
}
