import Foundation

/// A user-defined bucket. Items land in it either manually or via keyword rules.
struct Category: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var symbol: String = "folder"
    var colorHex: String = "#5B8CFF"
    /// Case-insensitive substrings; a new clip matching any of them is auto-filed here.
    var rules: [String] = []
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    func matches(_ item: ClipItem) -> Bool {
        guard !rules.isEmpty else { return false }
        let hay = item.searchText.lowercased()
        return rules.contains { !$0.isEmpty && hay.contains($0.lowercased()) }
    }

    static let starterPack: [Category] = [
        Category(name: "Work", symbol: "briefcase", colorHex: "#5B8CFF", rules: [], sortIndex: 0),
        Category(name: "Snippets", symbol: "curlybraces", colorHex: "#66C87C", rules: [], sortIndex: 1),
        Category(name: "Design", symbol: "paintbrush.pointed", colorHex: "#C88CFA", rules: [], sortIndex: 2)
    ]
}

/// The left-hand navigation selection in the library, and the filter for search.
enum Scope: Hashable {
    case all
    case pinned
    case kind(ItemKind)
    case app(String)          // bundle id
    case category(String)     // category id
    case tag(String)

    var isPinned: Bool { if case .pinned = self { return true }; return false }
}
