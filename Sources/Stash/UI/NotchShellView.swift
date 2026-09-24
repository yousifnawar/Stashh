import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The black shell that grows out of the notch. Collapsed it is invisible against
/// the real notch; expanded it is a full clip strip.
struct NotchShellView: View {
    /// `preselect` and `startTab` are hooks for the offscreen preview renderer.
    init(controller: NotchController, preselect: Int = 0, startTab: NotchTab = .clips) {
        self.controller = controller
        self.preselect = preselect
        _tab = State(initialValue: startTab)
    }
    private let preselect: Int

    @ObservedObject var controller: NotchController
    @ObservedObject private var store = ClipStore.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var filter: ItemKind?
    @State private var tab: NotchTab
    /// Clips picked with the selection circles, for dragging several out at once.
    @State private var selection: Set<String> = []
    /// Leading item of each strip, both read and written by its scrollbar.
    @State private var stripAnchor: String?
    @State private var shelfAnchor: String?

    private var shell: CGSize { controller.shellSize }
    private var notch: CGSize { controller.metrics.notchSize }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                BottomRoundedShape(radius: controller.state == .collapsed ? notchRadius : Theme.notchCornerRadius)
                    .fill(Theme.notchBackground)
                    .overlay(
                        BottomRoundedShape(radius: controller.state == .collapsed ? notchRadius : Theme.notchCornerRadius)
                            .stroke(Color.white.opacity(controller.state == .expanded ? 0.08 : 0), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(controller.state == .expanded ? 0.55 : 0),
                            radius: 26, x: 0, y: 14)

                content
                    .frame(width: shell.width, height: shell.height, alignment: .top)
                    .clipped()
            }
            .frame(width: shell.width, height: shell.height)
            .opacity(controller.state == .collapsed && controller.hidesWhenCollapsed ? 0 : 1)
            // The little concave joins that make the shell read as one object.
            .overlay(alignment: .topLeading) {
                if controller.state != .collapsed {
                    NotchFlare(size: 11).offset(x: -11, y: 0)
                }
            }
            .overlay(alignment: .topTrailing) {
                if controller.state != .collapsed {
                    NotchFlare(size: 11, flipped: true).offset(x: 11, y: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: NotchGeometry.windowSize.width,
               height: NotchGeometry.windowSize.height, alignment: .top)
        .coordinateSpace(name: StashSpace.root)
        .environment(\.pointerLocation, controller.pointer)
        .animation(Theme.snappy, value: controller.state)
        .onDrop(of: DropIngest.acceptedTypes, isTargeted: $controller.isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onChange(of: controller.isDropTargeted) { _, targeted in
            if targeted { controller.expand() }
        }
        .onChange(of: tab) { _, _ in selection.removeAll() }
        .onChange(of: controller.state) { _, state in
            // A closed shell forgets what was picked.
            if state != .expanded { selection.removeAll() }
        }
        .onAppear {
            guard preselect > 0, selection.isEmpty else { return }
            selection = Set(visibleItems.prefix(preselect).map(\.id))
        }
    }

    private var notchRadius: CGFloat { controller.metrics.hasRealNotch ? 10 : 12 }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .collapsed: collapsedContent
        case .dropZone:  dropZoneContent
        case .expanded:  expandedContent
        }
    }

    private var collapsedContent: some View {
        // On a real notch there is nothing to draw. On other displays we show a
        // small handle so the shell is discoverable.
        Group {
            if !controller.metrics.hasRealNotch, Settings.shared.notchOpensOnHover {
                HStack(spacing: 6) {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Stash").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The target that appears when a dragged file reaches the top of the screen.
    private var dropZoneContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: controller.isDropTargeted
                      ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(controller.isDropTargeted ? Theme.accent : Theme.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.isDropTargeted ? "Release to hold" : "Drop files here")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    Text("Park them for later")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: notch.width)

            HStack(spacing: 8) {
                if !shelf.isEmpty {
                    Text("\(shelf.items.count) on the shelf")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                }
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(controller.isDropTargeted ? Theme.accent : Theme.tertiary)
            }
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: NotchGeometry.dropZoneSize(notch: notch).height)
        .background(
            RoundedRectangle(cornerRadius: Theme.notchCornerRadius, style: .continuous)
                .strokeBorder(controller.isDropTargeted ? Theme.accent : Color.white.opacity(0.14),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
                .padding(.top, notch.height * 0.35)
        )
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.07))
            switch tab {
            case .clips:
                if visibleItems.isEmpty { emptyState } else { strip }
                footer
            case .shelf:
                if shelf.items.isEmpty { shelfEmptyState } else { shelfStrip }
                shelfFooter
            }
        }
        .frame(width: shell.width, height: shell.height)
    }

    // MARK: - Header (flanks the physical notch)

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                TabPill(title: "Clips", count: store.items.count,
                        active: tab == .clips) { tab = .clips }
                TabPill(title: "Shelf", count: shelf.items.count,
                        active: tab == .shelf, tint: Color(nsColor: ItemKind.file.accent)) {
                    tab = .shelf
                }
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: notch.width + 8)

            HStack(spacing: 6) {
                NotchButton(symbol: "magnifyingglass", help: "Quick Search  " + Shortcuts.shared.label(.quickSearch)) {
                    controller.collapse()
                    NotificationCenter.default.post(name: .stashShowQuickSearch, object: nil)
                }
                NotchButton(symbol: "square.grid.2x2", help: "Open Library  " + Shortcuts.shared.label(.library)) {
                    controller.collapse()
                    NotificationCenter.default.post(name: .stashShowLibrary, object: nil)
                }
                NotchButton(symbol: "xmark", help: "Close") { controller.collapse() }
            }
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: max(notch.height, 34))
    }

    // MARK: - Body

    private var visibleItems: [ClipItem] {
        let base = store.recent(60)
        guard let filter else { return base }
        return base.filter { $0.kind == filter }
    }

    private var strip: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(visibleItems) { item in
                        ClipTile(item: item, width: 146, height: 112,
                                 selected: selection.contains(item.id),
                                 multiDrag: multiDragSource(for: item),
                                 onToggleSelect: { toggle(item) },
                                 selectionActive: !selection.isEmpty,
                                 onActivate: {
                                     // Once picking has started, a plain click keeps
                                     // picking rather than pasting and closing.
                                     if selection.isEmpty { controller.activate(item) }
                                     else { toggle(item) }
                                 })
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollPosition(id: $stripAnchor)
            .frame(height: 136)

            StripScrollBar(count: visibleItems.count,
                           index: anchorBinding($stripAnchor, items: visibleItems))
                .padding(.horizontal, 16)
        }
    }

    /// Maps a scrollbar position onto the item sitting at the strip's leading edge.
    private func anchorBinding(_ anchor: Binding<String?>, items: [ClipItem]) -> Binding<Int> {
        Binding(
            get: { items.firstIndex { $0.id == anchor.wrappedValue } ?? 0 },
            set: { index in
                guard items.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.14)) { anchor.wrappedValue = items[index].id }
            })
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: controller.isDropTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 20))
                .foregroundStyle(Theme.tertiary)
            Text(controller.isDropTargeted ? "Drop to stash" :
                    (filter == nil ? "Nothing stashed yet — copy something" : "Nothing here yet"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 136)
    }

    // MARK: - Footer filters

    private var footer: some View {
        HStack(spacing: 6) {
            FilterChip(title: "All", symbol: "square.grid.2x2",
                       active: filter == nil, tint: Theme.accent) { filter = nil }
            ForEach(availableKinds, id: \.self) { kind in
                FilterChip(title: kind.title, symbol: kind.symbol,
                           active: filter == kind, tint: kind.color) {
                    filter = (filter == kind) ? nil : kind
                }
            }
            Spacer(minLength: 0)
            if controller.isDropTargeted {
                Label("Drop to stash", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            } else if !selection.isEmpty {
                HStack(spacing: 7) {
                    Text(selection.count == 1
                         ? "1 selected · pick more"
                         : "\(selection.count) selected · drag to take all")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Button("Clear") { selection.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                }
            } else if controller.openedByShortcut, !Shortcuts.shared.label(.notch).isEmpty {
                Text("\(Shortcuts.shared.label(.notch)) to close")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
            } else {
                Text("drag out · click to paste")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 2)
        .frame(height: 42)
    }

    // MARK: - Shelf

    private var shelfStrip: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(shelf.items) { item in
                        ClipTile(item: item, width: 146, height: 112,
                                 selected: selection.contains(item.id),
                                 multiDrag: shelfMultiDragSource(for: item),
                                 onToggleSelect: { toggle(item) },
                                 selectionActive: !selection.isEmpty,
                                 onActivate: {
                                     if selection.isEmpty { revealOrOpen(item) } else { toggle(item) }
                                 })
                            .opacity(ShelfStore.isMissing(item) ? 0.45 : 1)
                            .overlay(alignment: .topTrailing) { removeButton(item) }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollPosition(id: $shelfAnchor)
            .frame(height: 136)

            StripScrollBar(count: shelf.items.count,
                           index: anchorBinding($shelfAnchor, items: shelf.items))
                .padding(.horizontal, 16)
        }
    }

    private func removeButton(_ item: ClipItem) -> some View {
        ShelfRemoveButton { shelf.remove(item) }
    }

    private var shelfEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20))
                .foregroundStyle(Theme.tertiary)
            Text("Drag a file to the top of the screen to park it here")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 136)
    }

    private var shelfFooter: some View {
        HStack(spacing: 8) {
            if !selection.isEmpty {
                Text(selection.count == 1 ? "1 selected · pick more"
                                          : "\(selection.count) selected · drag to take all")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Button("Clear") { selection.removeAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Button("Remove") { shelf.remove(selectedShelfItems); selection.removeAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10)).foregroundStyle(.red.opacity(0.9))
            } else if !shelf.isEmpty {
                Text("drag out to move · click to reveal in Finder")
                    .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            }
            Spacer(minLength: 0)
            if !shelf.isEmpty {
                Button("Empty Shelf") {
                    shelf.clear()
                    selection.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 2)
        .frame(height: 42)
    }

    private var selectedShelfItems: [ClipItem] {
        shelf.items.filter { selection.contains($0.id) }
    }

    private func shelfMultiDragSource(for item: ClipItem) -> (() -> [ClipItem])? {
        guard selection.count > 1, selection.contains(item.id) else { return nil }
        return { selectedShelfItems }
    }

    private func revealOrOpen(_ item: ClipItem) {
        guard let url = ShelfStore.url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Selection

    private var selectedItems: [ClipItem] {
        visibleItems.filter { selection.contains($0.id) }
    }

    private func toggle(_ item: ClipItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    private func multiDragSource(for item: ClipItem) -> (() -> [ClipItem])? {
        guard selection.count > 1, selection.contains(item.id) else { return nil }
        return { selectedItems }
    }

    private var availableKinds: [ItemKind] {
        let present = Set(store.items.prefix(400).map(\.kind))
        return ItemKind.allCases.filter { present.contains($0) }
    }

    // MARK: - Drop

    /// Files dropped on the notch are parked on the shelf, not filed into the
    /// permanent history — that is what the library window is for.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        DropIngest.collect(providers) { payloads in
            guard !payloads.isEmpty else { return }
            let added = shelf.add(payloads: payloads)
            if added > 0 { tab = .shelf }
            controller.expand()
        }
        return true
    }
}

// MARK: - Small controls

enum NotchTab { case clips, shelf }

/// A draggable bar under a strip, for walking through clips that run off the
/// right-hand edge without a trackpad swipe.
struct StripScrollBar: View {
    let count: Int
    var visibleCount: Int = 4
    @Binding var index: Int
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let maxIndex = max(count - visibleCount, 0)
            if maxIndex > 0 {
                let width = geo.size.width
                let thumb = max(44, width * CGFloat(visibleCount) / CGFloat(max(count, 1)))
                let travel = max(width - thumb, 1)
                let fraction = CGFloat(min(max(index, 0), maxIndex)) / CGFloat(maxIndex)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                    Capsule().fill(Color.white.opacity(dragging ? 0.6 : 0.32))
                        .frame(width: thumb, height: 5)
                        .offset(x: travel * fraction)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            let x = min(max(value.location.x - thumb / 2, 0), travel)
                            index = Int(round(x / travel * CGFloat(maxIndex)))
                        }
                        .onEnded { _ in dragging = false }
                )
            }
        }
        .frame(height: 16)
    }
}

/// Sits quietly in the corner of a shelf tile until you reach for it.
struct ShelfRemoveButton: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.75))
                .padding(3.5)
                .background(Circle().fill(Color.black.opacity(hovering ? 0.85 : 0.45)))
        }
        .buttonStyle(.plain)
        .padding(5)
        .stashHover($hovering)
        .help("Take off the shelf")
    }
}

struct TabPill: View {
    let title: String
    let count: Int
    let active: Bool
    var tint: Color = Theme.accent
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundStyle(active ? Color.black.opacity(0.85)
                                    : (hovering ? Theme.primary : Theme.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule().fill(active ? tint
                               : (hovering ? Color.white.opacity(0.12) : Color.white.opacity(0.06)))
            )
        }
        .buttonStyle(.plain)
        .stashHover($hovering)
    }
}

struct NotchButton: View {
    let symbol: String
    var help: String = ""
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.primary : Theme.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.13) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .stashHover($hovering)
        .help(help)
    }
}

struct FilterChip: View {
    let title: String
    let symbol: String
    let active: Bool
    var tint: Color = Theme.accent
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(active ? Color.black.opacity(0.85) : (hovering ? Theme.primary : Theme.secondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule().fill(active ? tint : (hovering ? Color.white.opacity(0.12) : Color.white.opacity(0.06)))
            )
        }
        .buttonStyle(.plain)
        .stashHover($hovering)
    }
}
