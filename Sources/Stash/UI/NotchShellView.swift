import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The black shell that grows out of the notch. Collapsed it is invisible against
/// the real notch; expanded it is a full clip strip.
struct NotchShellView: View {
    /// `preselect` is a hook for the offscreen preview renderer.
    init(controller: NotchController, preselect: Int = 0) {
        self.controller = controller
        self.preselect = preselect
    }
    private let preselect: Int

    @ObservedObject var controller: NotchController
    @ObservedObject private var store = ClipStore.shared
    @State private var filter: ItemKind?
    /// Clips picked with the selection circles, for dragging several out at once.
    @State private var selection: Set<String> = []

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

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.07))
            if visibleItems.isEmpty {
                emptyState
            } else {
                strip
            }
            footer
        }
        .frame(width: shell.width, height: shell.height)
    }

    // MARK: - Header (flanks the physical notch)

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Stash")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text("\(store.items.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .padding(.leading, 18)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visibleItems) { item in
                    ClipTile(item: item, width: 146, height: 112,
                             selected: selection.contains(item.id),
                             multiDrag: multiDragSource(for: item),
                             onToggleSelect: { toggle(item) },
                             onActivate: { controller.activate(item) })
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 136)
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        DropIngest.collect(providers) { payloads in
            guard !payloads.isEmpty else { return }
            Paster.ingestDropped(payloads)
            controller.expand()
        }
        return true
    }
}

// MARK: - Small controls

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
