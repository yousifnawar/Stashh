import Foundation
import AppKit
import Combine

/// The single source of truth. Owns the SQLite file, keeps a recent working set in
/// memory for instant search, and publishes changes to every window.
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    /// Newest first. Capped at `workingSetLimit`; older rows stay on disk.
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var categories: [Category] = []
    /// Bumped whenever a clip is captured, so the notch can pulse.
    @Published private(set) var lastCaptured: ClipItem?

    private let workingSetLimit = 4000
    private var db: Database?
    private let queue = DispatchQueue(label: "com.nawar.stash.store", qos: .userInitiated)

    private init() {
        do {
            let db = try Database(path: Paths.database.path)
            self.db = db
            try migrate(db)
            load()
        } catch {
            NSLog("[Stash] store init failed: \(error)")
        }
    }

    // MARK: - Schema

    private func migrate(_ db: Database) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            created_at REAL NOT NULL,
            last_used_at REAL,
            use_count INTEGER NOT NULL DEFAULT 0,
            app_name TEXT NOT NULL DEFAULT '',
            app_bundle TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            preview TEXT NOT NULL DEFAULT '',
            text TEXT,
            rtf_path TEXT,
            blob_path TEXT,
            thumb_path TEXT,
            file_urls TEXT NOT NULL DEFAULT '[]',
            pixel_width INTEGER NOT NULL DEFAULT 0,
            pixel_height INTEGER NOT NULL DEFAULT 0,
            byte_size INTEGER NOT NULL DEFAULT 0,
            color_hex TEXT,
            pinned INTEGER NOT NULL DEFAULT 0,
            tags TEXT NOT NULL DEFAULT '[]',
            category_ids TEXT NOT NULL DEFAULT '[]',
            content_hash TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_hash ON items(content_hash);
        CREATE INDEX IF NOT EXISTS idx_items_kind ON items(kind);

        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            symbol TEXT NOT NULL DEFAULT 'folder',
            color_hex TEXT NOT NULL DEFAULT '#5B8CFF',
            rules TEXT NOT NULL DEFAULT '[]',
            sort_index INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        """)
    }

    // MARK: - Loading

    private func load() {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            do {
                let rows = try db.query(
                    "SELECT * FROM items ORDER BY created_at DESC LIMIT ?",
                    [.int(self.workingSetLimit)])
                let loaded = rows.map(Self.item(from:))

                var cats = try db.query("SELECT * FROM categories ORDER BY sort_index ASC")
                    .map(Self.category(from:))
                if cats.isEmpty {
                    cats = Category.starterPack
                    for c in cats { try? self.insert(category: c, db: db) }
                }
                DispatchQueue.main.async {
                    // Anything captured while this read was in flight is already in
                    // memory (and on disk); merge rather than replace it.
                    let loadedIDs = Set(loaded.map(\.id))
                    let inFlight = self.items.filter { !loadedIDs.contains($0.id) }
                    self.items = (inFlight + loaded).sorted { $0.createdAt > $1.createdAt }
                    self.categories = cats
                }
            } catch {
                NSLog("[Stash] load failed: \(error)")
            }
        }
    }

    // MARK: - Capture

    /// Inserts a clip, folding it into an existing identical one when the content matches.
    func add(_ item: ClipItem) {
        var item = item
        // Auto-file into any category whose rules match.
        let matching = categories.filter { $0.matches(item) }.map(\.id)
        item.categoryIDs = Array(Set(item.categoryIDs + matching))

        if let existing = items.first(where: { $0.contentHash == item.contentHash && !item.contentHash.isEmpty }) {
            // Same content copied again: float it to the top instead of duplicating.
            var bumped = existing
            bumped.createdAt = Date()
            bumped.useCount += 1
            bumped.appName = item.appName.isEmpty ? existing.appName : item.appName
            bumped.appBundleID = item.appBundleID.isEmpty ? existing.appBundleID : item.appBundleID
            update(bumped, announce: true)
            return
        }

        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            if self.items.count > self.workingSetLimit { self.items.removeLast() }
            self.lastCaptured = item
        }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            do { try self.insert(item: item, db: db) }
            catch { NSLog("[Stash] insert failed: \(error)") }
        }
    }

    // MARK: - Mutation

    func update(_ item: ClipItem, announce: Bool = false) {
        DispatchQueue.main.async {
            if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[idx] = item
            } else {
                self.items.insert(item, at: 0)
            }
            self.items.sort { lhs, rhs in lhs.createdAt > rhs.createdAt }
            if announce { self.lastCaptured = item }
        }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            try? self.insert(item: item, db: db)   // INSERT OR REPLACE
        }
    }

    func togglePin(_ item: ClipItem) {
        var copy = item
        copy.pinned.toggle()
        update(copy)
    }

    func markUsed(_ item: ClipItem) {
        var copy = item
        copy.useCount += 1
        copy.lastUsedAt = Date()
        update(copy)
    }

    func setCategories(_ ids: [String], for item: ClipItem) {
        var copy = item
        copy.categoryIDs = ids
        update(copy)
    }

    func setTags(_ tags: [String], for item: ClipItem) {
        var copy = item
        copy.tags = tags
        update(copy)
    }

    func rename(_ item: ClipItem, to title: String) {
        var copy = item
        copy.title = title.trimmed.isEmpty ? item.preview.firstLine.truncated(60) : title.trimmed
        update(copy)
    }

    func delete(_ item: ClipItem) {
        DispatchQueue.main.async { self.items.removeAll { $0.id == item.id } }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            try? db.run("DELETE FROM items WHERE id = ?", [.text(item.id)])
            for p in [item.blobPath, item.thumbPath, item.rtfPath].compactMap({ $0 }) {
                try? FileManager.default.removeItem(atPath: p)
            }
        }
    }

    func deleteAll(keepPinned: Bool = true) {
        let doomed = items.filter { keepPinned ? !$0.pinned : true }
        DispatchQueue.main.async { self.items.removeAll { keepPinned ? !$0.pinned : true } }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            try? db.run(keepPinned ? "DELETE FROM items WHERE pinned = 0" : "DELETE FROM items")
            for item in doomed {
                for p in [item.blobPath, item.thumbPath, item.rtfPath].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(atPath: p)
                }
            }
        }
    }

    /// Drops unpinned clips older than `days`. Called on launch and daily.
    func prune(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let doomed = items.filter { !$0.pinned && $0.createdAt < cutoff }
        guard !doomed.isEmpty else { return }
        DispatchQueue.main.async {
            self.items.removeAll { !$0.pinned && $0.createdAt < cutoff }
        }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            try? db.run("DELETE FROM items WHERE pinned = 0 AND created_at < ?",
                        [.double(cutoff.timeIntervalSince1970)])
            for item in doomed {
                for p in [item.blobPath, item.thumbPath, item.rtfPath].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(atPath: p)
                }
            }
        }
    }

    // MARK: - Categories

    func addCategory(_ c: Category) {
        DispatchQueue.main.async { self.categories.append(c) }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            try? self.insert(category: c, db: db)
        }
    }

    func updateCategory(_ c: Category) {
        DispatchQueue.main.async {
            if let i = self.categories.firstIndex(where: { $0.id == c.id }) { self.categories[i] = c }
        }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            try? self.insert(category: c, db: db)
        }
    }

    func deleteCategory(_ c: Category) {
        DispatchQueue.main.async {
            self.categories.removeAll { $0.id == c.id }
            for i in self.items.indices { self.items[i].categoryIDs.removeAll { $0 == c.id } }
        }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            try? db.run("DELETE FROM categories WHERE id = ?", [.text(c.id)])
        }
    }

    func category(id: String) -> Category? { categories.first { $0.id == id } }

    // MARK: - Querying

    /// Every distinct source app in the working set, most-used first.
    var apps: [(bundleID: String, name: String, count: Int)] {
        var tally: [String: (String, Int)] = [:]
        for item in items where !item.appBundleID.isEmpty {
            let cur = tally[item.appBundleID] ?? (item.appName, 0)
            tally[item.appBundleID] = (cur.0.isEmpty ? item.appName : cur.0, cur.1 + 1)
        }
        return tally.map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.count > $1.count }
    }

    var allTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted()
    }

    func count(for scope: Scope) -> Int { items.filter { matches($0, scope) }.count }

    func matches(_ item: ClipItem, _ scope: Scope) -> Bool {
        switch scope {
        case .all: return true
        case .pinned: return item.pinned
        case .kind(let k): return item.kind == k
        case .app(let b): return item.appBundleID == b
        case .category(let id): return item.categoryIDs.contains(id)
        case .tag(let t): return item.tags.contains(t)
        }
    }

    /// Scope filter + fuzzy ranking. Pinned clips win ties.
    func search(_ query: String, scope: Scope = .all, limit: Int = 400) -> [ClipItem] {
        let pool = items.filter { matches($0, scope) }
        let q = query.trimmed
        guard !q.isEmpty else { return Array(pool.prefix(limit)) }

        var scored: [(ClipItem, Double)] = []
        for item in pool {
            guard var s = Fuzzy.score(q, item.searchText) else { continue }
            if item.pinned { s += 4 }
            s += min(Double(item.useCount), 6) * 0.5
            s -= Date().timeIntervalSince(item.createdAt) / 86_400 * 0.15   // mild recency tilt
            scored.append((item, s))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    func recent(_ n: Int) -> [ClipItem] {
        let pinned = items.filter(\.pinned)
        let rest = items.filter { !$0.pinned }
        return Array((pinned + rest).prefix(n))
    }

    // MARK: - Row mapping

    private func insert(item: ClipItem, db: Database) throws {
        try db.run("""
        INSERT OR REPLACE INTO items
        (id, kind, created_at, last_used_at, use_count, app_name, app_bundle, title, preview,
         text, rtf_path, blob_path, thumb_path, file_urls, pixel_width, pixel_height, byte_size,
         color_hex, pinned, tags, category_ids, content_hash)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, [
            .text(item.id), .text(item.kind.rawValue),
            .double(item.createdAt.timeIntervalSince1970), .date(item.lastUsedAt),
            .int(item.useCount), .text(item.appName), .text(item.appBundleID),
            .text(item.title), .text(item.preview), .opt(item.text), .opt(item.rtfPath),
            .opt(item.blobPath), .opt(item.thumbPath), .text(JSONBox.encode(item.fileURLs)),
            .int(item.pixelWidth), .int(item.pixelHeight), .int(item.byteSize),
            .opt(item.colorHex), .bool(item.pinned), .text(JSONBox.encode(item.tags)),
            .text(JSONBox.encode(item.categoryIDs)), .text(item.contentHash)
        ])
    }

    private func insert(category: Category, db: Database) throws {
        try db.run("""
        INSERT OR REPLACE INTO categories (id, name, symbol, color_hex, rules, sort_index, created_at)
        VALUES (?,?,?,?,?,?,?)
        """, [
            .text(category.id), .text(category.name), .text(category.symbol),
            .text(category.colorHex), .text(JSONBox.encode(category.rules)),
            .int(category.sortIndex), .double(category.createdAt.timeIntervalSince1970)
        ])
    }

    private static func item(from row: Database.Row) -> ClipItem {
        var i = ClipItem()
        i.id = row.string("id") ?? UUID().uuidString
        i.kind = ItemKind(rawValue: row.string("kind") ?? "text") ?? .text
        i.createdAt = row.date("created_at") ?? Date()
        i.lastUsedAt = row.date("last_used_at")
        i.useCount = row.int("use_count")
        i.appName = row.string("app_name") ?? ""
        i.appBundleID = row.string("app_bundle") ?? ""
        i.title = row.string("title") ?? ""
        i.preview = row.string("preview") ?? ""
        i.text = row.string("text")
        i.rtfPath = row.string("rtf_path")
        i.blobPath = row.string("blob_path")
        i.thumbPath = row.string("thumb_path")
        i.fileURLs = JSONBox.decode(row.string("file_urls"), [String].self, default: [])
        i.pixelWidth = row.int("pixel_width")
        i.pixelHeight = row.int("pixel_height")
        i.byteSize = row.int("byte_size")
        i.colorHex = row.string("color_hex")
        i.pinned = row.bool("pinned")
        i.tags = JSONBox.decode(row.string("tags"), [String].self, default: [])
        i.categoryIDs = JSONBox.decode(row.string("category_ids"), [String].self, default: [])
        i.contentHash = row.string("content_hash") ?? ""
        return i
    }

    private static func category(from row: Database.Row) -> Category {
        var c = Category(name: row.string("name") ?? "Untitled")
        c.id = row.string("id") ?? UUID().uuidString
        c.symbol = row.string("symbol") ?? "folder"
        c.colorHex = row.string("color_hex") ?? "#5B8CFF"
        c.rules = JSONBox.decode(row.string("rules"), [String].self, default: [])
        c.sortIndex = row.int("sort_index")
        c.createdAt = row.date("created_at") ?? Date()
        return c
    }
}
