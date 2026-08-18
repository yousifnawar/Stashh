import Foundation
import AppKit

/// What a clip fundamentally *is*. Drives grouping, iconography and paste behaviour.
enum ItemKind: String, Codable, CaseIterable {
    case text
    case link
    case code
    case color
    case image
    case screenshot
    case file
    case richText

    var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Links"
        case .code: return "Code"
        case .color: return "Colors"
        case .image: return "Images"
        case .screenshot: return "Screenshots"
        case .file: return "Files"
        case .richText: return "Rich Text"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .screenshot: return "camera.viewfinder"
        case .file: return "doc"
        case .richText: return "doc.richtext"
        }
    }

    var accent: NSColor {
        switch self {
        case .text: return NSColor(srgbRed: 0.62, green: 0.66, blue: 0.74, alpha: 1)
        case .link: return NSColor(srgbRed: 0.36, green: 0.62, blue: 1.00, alpha: 1)
        case .code: return NSColor(srgbRed: 0.55, green: 0.83, blue: 0.55, alpha: 1)
        case .color: return NSColor(srgbRed: 0.95, green: 0.71, blue: 0.35, alpha: 1)
        case .image: return NSColor(srgbRed: 0.78, green: 0.55, blue: 0.98, alpha: 1)
        case .screenshot: return NSColor(srgbRed: 0.98, green: 0.52, blue: 0.62, alpha: 1)
        case .file: return NSColor(srgbRed: 0.45, green: 0.78, blue: 0.86, alpha: 1)
        case .richText: return NSColor(srgbRed: 0.88, green: 0.62, blue: 0.42, alpha: 1)
        }
    }

    var isVisual: Bool { self == .image || self == .screenshot }
}

struct ClipItem: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var kind: ItemKind = .text
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0

    var appName: String = ""
    var appBundleID: String = ""

    /// Short human label shown on the card.
    var title: String = ""
    /// Up to a few hundred characters used for card bodies and previews.
    var preview: String = ""
    /// The full plaintext payload (nil for pure-binary clips).
    var text: String?
    /// RTF payload path, if the clip carried styled text.
    var rtfPath: String?
    /// Absolute path of the stored image / file copy.
    var blobPath: String?
    var thumbPath: String?
    /// Original file URLs for file clips (they may still exist in place).
    var fileURLs: [String] = []

    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var byteSize: Int = 0
    var colorHex: String?

    var pinned: Bool = false
    var tags: [String] = []
    var categoryIDs: [String] = []

    /// Content fingerprint used for de-duplication.
    var contentHash: String = ""

    // MARK: Derived

    var searchText: String {
        var parts = [title, preview, appName, kind.title]
        parts.append(contentsOf: tags)
        parts.append(contentsOf: fileURLs.map { ($0 as NSString).lastPathComponent })
        if let c = colorHex { parts.append(c) }
        return parts.joined(separator: " ")
    }

    var thumbnail: NSImage? {
        if let p = thumbPath, let img = NSImage(contentsOfFile: p) { return img }
        if let p = blobPath, let img = NSImage(contentsOfFile: p) { return img }
        return nil
    }

    var displayColor: NSColor? {
        guard let hex = colorHex else { return nil }
        return NSColor(hex: hex)
    }

    var byteSizeLabel: String {
        guard byteSize > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    var dimensionLabel: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "" }
        return "\(pixelWidth)×\(pixelHeight)"
    }

    var relativeTime: String { RelativeTime.string(for: createdAt) }

    var host: String? {
        guard kind == .link, let t = text, let url = URL(string: t.trimmed) else { return nil }
        return url.host
    }
}

enum RelativeTime {
    private static let fmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func string(for date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "just now" }
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    static func dayBucket(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            let f = DateFormatter(); f.dateFormat = "EEEE"
            return f.string(from: date)
        }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }
}
