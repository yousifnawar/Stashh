import SwiftUI
import AppKit

final class LibraryWindowController: NSObject, NSWindowDelegate {
    static let shared = LibraryWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil { build() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if window?.isVisible == true { window?.orderOut(nil) } else { show() }
    }

    private func build() {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1120, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Stash"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.minSize = NSSize(width: 880, height: 560)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.backgroundColor = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 1)

        let host = NSHostingView(rootView: LibraryView())
        w.contentView = host
        window = w
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only app when the library is dismissed.
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}

struct LibraryView: View {
    /// Preselects the first N clips — used by the offscreen preview renderer.
    init(preselect: Int = 0) { self.preselect = preselect }
    private let preselect: Int

    @ObservedObject private var store = ClipStore.shared
    @State private var scope: Scope = .all
    @State private var query: String = ""
    @State private var selection: Set<String> = []
    /// Anchor for shift-click range selection.
    @State private var anchor: String?
    @State private var dropTargeted = false
    @State private var layout: LayoutMode = .grid
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""

    enum LayoutMode: String { case grid, list }

    private var results: [ClipItem] { store.search(query, scope: scope, limit: 1000) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.stroke)
            VStack(spacing: 0) {
                toolbar
                Divider().overlay(Theme.stroke)
                if results.isEmpty { emptyState } else { body(for: layout) }
            }
            .overlay { if dropTargeted { dropOverlay } }
            .onDrop(of: DropIngest.acceptedTypes, isTargeted: $dropTargeted) { providers in
                DropIngest.collect(providers) { payloads in
                    Paster.ingestDropped(payloads)
                }
                return true
            }

            if selection.count == 1, let item = selectedItems.first {
                Divider().overlay(Theme.stroke)
                InspectorView(item: item) { clearSelection() }
                    .frame(width: 300)
                    .transition(.move(edge: .trailing))
            } else if selection.count > 1 {
                Divider().overlay(Theme.stroke)
                MultiSelectionInspector(items: selectedItems) { clearSelection() }
                    .frame(width: 300)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .animation(Theme.quick, value: selection.count)
        .onDeleteCommand { deleteSelection() }
        .onExitCommand { clearSelection() }
        .onChange(of: scopeKey) { _, _ in clearSelection() }
        .onAppear {
            guard preselect > 0, selection.isEmpty else { return }
            selection = Set(orderedItems.prefix(preselect).map(\.id))
        }
    }

    // MARK: - Selection

    /// Flat, on-screen order — what shift-click ranges over.
    private var orderedItems: [ClipItem] {
        layout == .grid ? sections.flatMap(\.items) : results
    }

    private var selectedItems: [ClipItem] {
        orderedItems.filter { selection.contains($0.id) }
    }

    private var scopeKey: String { "\(scopeTitle)|\(query)" }

    /// ⌘-click toggles, ⇧-click extends from the anchor, a plain click replaces.
    private func select(_ item: ClipItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchor = item.id
        } else if flags.contains(.shift), let anchor,
                  let from = orderedItems.firstIndex(where: { $0.id == anchor }),
                  let to = orderedItems.firstIndex(where: { $0.id == item.id }) {
            let range = from <= to ? from...to : to...from
            selection.formUnion(orderedItems[range].map(\.id))
        } else {
            selection = [item.id]
            anchor = item.id
        }
    }

    /// The checkbox path: always additive, never replaces what is already picked.
    private func toggle(_ item: ClipItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        anchor = item.id
    }

    private func clearSelection() {
        selection.removeAll()
        anchor = nil
    }

    private func deleteSelection() {
        for item in selectedItems { store.delete(item) }
        clearSelection()
    }

    /// Handed to tiles that are part of a multi-selection.
    private func multiDragSource(for item: ClipItem) -> (() -> [ClipItem])? {
        guard selection.count > 1, selection.contains(item.id) else { return nil }
        return { selectedItems }
    }

    private var dropOverlay: some View {
        ZStack {
            Theme.accent.opacity(0.10)
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 30)).foregroundStyle(Theme.accent)
                Text("Drop to stash")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.primary)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func body(for mode: LayoutMode) -> some View {
        switch mode {
        case .grid: grid
        case .list: list
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.on.square.dashed")
                    .foregroundStyle(Theme.accent)
                Text("Stash").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSection("Library")
                    SidebarRow(title: "All Clips", symbol: "tray.full",
                               count: store.items.count,
                               active: scope == .all) { scope = .all }
                    SidebarRow(title: "Pinned", symbol: "pin.fill",
                               count: store.count(for: .pinned), tint: .yellow,
                               active: scope == .pinned) { scope = .pinned }

                    SidebarSection("Types")
                    ForEach(ItemKind.allCases, id: \.self) { kind in
                        let n = store.count(for: .kind(kind))
                        if n > 0 {
                            SidebarRow(title: kind.title, symbol: kind.symbol, count: n,
                                       tint: kind.color, active: scope == .kind(kind)) {
                                scope = .kind(kind)
                            }
                        }
                    }

                    let apps = store.apps
                    if !apps.isEmpty {
                        SidebarSection("Apps")
                        ForEach(apps.prefix(10), id: \.bundleID) { app in
                            SidebarRow(title: app.name.isEmpty ? app.bundleID : app.name,
                                       symbol: nil, bundleID: app.bundleID, count: app.count,
                                       active: scope == .app(app.bundleID)) {
                                scope = .app(app.bundleID)
                            }
                        }
                    }

                    HStack {
                        SidebarSection("Categories")
                        Spacer()
                        Button { showingNewCategory = true } label: {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.tertiary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                    }
                    ForEach(store.categories) { cat in
                        SidebarRow(title: cat.name, symbol: cat.symbol,
                                   count: store.count(for: .category(cat.id)),
                                   tint: Color(hex: cat.colorHex),
                                   active: scope == .category(cat.id)) {
                            scope = .category(cat.id)
                        }
                        .contextMenu {
                            Button("Delete Category", role: .destructive) {
                                store.deleteCategory(cat)
                                if scope == .category(cat.id) { scope = .all }
                            }
                        }
                    }

                    let tags = store.allTags
                    if !tags.isEmpty {
                        SidebarSection("Tags")
                        ForEach(tags, id: \.self) { tag in
                            SidebarRow(title: "#\(tag)", symbol: "number",
                                       count: store.count(for: .tag(tag)),
                                       active: scope == .tag(tag)) { scope = .tag(tag) }
                        }
                    }
                }
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
            Divider().overlay(Theme.stroke)
            HStack(spacing: 8) {
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 218)
        .background(Color.black.opacity(0.22))
        .alert("New Category", isPresented: $showingNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Create") {
                let name = newCategoryName.trimmed
                guard !name.isEmpty else { return }
                store.addCategory(Category(name: name, sortIndex: store.categories.count))
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                TextField("Search \(scopeTitle.lowercased())…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primary)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
            .frame(maxWidth: 380)

            if selection.count > 1 {
                HStack(spacing: 6) {
                    Text("\(selection.count) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.primary)
                    Button("Clear") { clearSelection() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Theme.accentSoft))
            } else if selection.count == 1 {
                Text("click the circles to pick more")
                    .font(.system(size: 11)).foregroundStyle(Theme.accent)
            } else {
                Text("\(results.count) items")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }

            Spacer()

            if !orderedItems.isEmpty {
                Button("Select All") { selection = Set(orderedItems.map(\.id)) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .keyboardShortcut("a", modifiers: .command)
            }

            Picker("", selection: $layout) {
                Image(systemName: "square.grid.2x2").tag(LayoutMode.grid)
                Image(systemName: "list.bullet").tag(LayoutMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)

            Menu {
                Button("Clear Unpinned…") { store.deleteAll(keepPinned: true) }
                Button("Clear Everything…", role: .destructive) { store.deleteAll(keepPinned: false) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var scopeTitle: String {
        switch scope {
        case .all: return "All Clips"
        case .pinned: return "Pinned"
        case .kind(let k): return k.title
        case .app(let b): return store.apps.first { $0.bundleID == b }?.name ?? "App"
        case .category(let id): return store.category(id: id)?.name ?? "Category"
        case .tag(let t): return "#\(t)"
        }
    }

    // MARK: - Content

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 196, maximum: 300), spacing: 14)]
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(section.items) { item in
                                ClipTile(item: item, width: nil, height: 156,
                                         selected: selection.contains(item.id),
                                         multiDrag: multiDragSource(for: item),
                                         onToggleSelect: { toggle(item) },
                                         selectionActive: !selection.isEmpty,
                                         onActivate: { select(item) },
                                         onDoubleActivate: { Paster.paste(item) })
                            }
                        }
                        .padding(.horizontal, 18)
                    } header: {
                        HStack {
                            Text(section.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                            Text("\(section.items.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.tertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(Theme.panel.opacity(0.96))
                    }
                }
            }
            .padding(.vertical, 14)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(results) { item in
                    ClipRow(item: item, selected: selection.contains(item.id)) {
                        select(item)
                    }
                }
            }
            .padding(12)
        }
    }

    private struct Section2: Hashable { var title: String; var items: [ClipItem] }

    private var sections: [Section2] {
        var order: [String] = []
        var buckets: [String: [ClipItem]] = [:]
        let pinned = results.filter(\.pinned)
        if !pinned.isEmpty {
            order.append("Pinned")
            buckets["Pinned"] = pinned
        }
        for item in results where !item.pinned {
            let key = RelativeTime.dayBucket(for: item.createdAt)
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(item)
        }
        return order.map { Section2(title: $0, items: buckets[$0] ?? []) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34)).foregroundStyle(Theme.tertiary)
            Text(query.isEmpty ? "Nothing in \(scopeTitle) yet" : "No matches for “\(query)”")
                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
            if query.isEmpty {
                Text("Copy something, take a screenshot, or drag images in here — it all lands automatically.")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar pieces

struct SidebarSection: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(Theme.tertiary)
            .tracking(0.6)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

struct SidebarRow: View {
    let title: String
    var symbol: String?
    var bundleID: String?
    var count: Int
    var tint: Color = Theme.secondary
    var active: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let bundleID {
                    AppBadge(bundleID: bundleID, size: 14)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(active ? tint : Theme.secondary)
                        .frame(width: 15)
                }
                Text(title)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.primary : Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.white.opacity(0.11) : (hovering ? Color.white.opacity(0.05) : .clear))
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
