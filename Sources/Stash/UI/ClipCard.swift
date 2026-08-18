import SwiftUI
import AppKit

/// The visual body of a clip — image, colour swatch, code, link or plain text.
struct ClipPreview: View {
    let item: ClipItem
    var compact: Bool = false
    /// Keeps the top-left corner clear for a selection circle, so text never
    /// disappears underneath it.
    var reserveCorner: Bool = false

    private var cornerInset: CGFloat { reserveCorner ? 17 : 0 }

    var body: some View {
        switch item.kind {
        case .image, .screenshot:
            if let thumb = item.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }

        case .color:
            ZStack {
                Color(nsColor: item.displayColor ?? .gray)
                Text(item.colorHex ?? "")
                    .font(.system(size: compact ? 10 : 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle((item.displayColor?.isLight ?? false) ? .black : .white)
            }

        case .file:
            HStack(spacing: 8) {
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: compact ? 26 : 34, height: compact ? 26 : 34)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: compact ? 18 : 24))
                        .foregroundStyle(item.kind.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).lineLimit(1)
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(Theme.primary)
                    if !item.byteSizeLabel.isEmpty {
                        Text(item.byteSizeLabel)
                            .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        case .code:
            Text(item.preview.truncated(compact ? 180 : 900))
                .font(.system(size: compact ? 9.5 : 11, design: .monospaced))
                .foregroundStyle(Theme.primary)
                .lineSpacing(1.5)
                .padding(10)
                .padding(.top, cornerInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: compact ? 12 : 15, weight: .semibold))
                    .foregroundStyle(item.kind.color)
                Text(item.title)
                    .font(.system(size: compact ? 11 : 12.5, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(10)
            .padding(.top, cornerInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        default:
            Text(item.preview.truncated(compact ? 200 : 1200))
                .font(.system(size: compact ? 10.5 : 12))
                .foregroundStyle(Theme.primary)
                .lineSpacing(2)
                .padding(10)
                .padding(.top, cornerInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.panelRaised
            Image(systemName: item.kind.symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Small square thumbnail for dense rows. Text-ish clips get their type glyph
/// rather than an unreadable sliver of their content.
struct ClipThumb: View {
    let item: ClipItem

    var body: some View {
        switch item.kind {
        case .image, .screenshot, .color:
            ClipPreview(item: item, compact: true)
        case .file:
            if let thumb = item.thumbnail {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
            } else {
                glyph
            }
        default:
            glyph
        }
    }

    private var glyph: some View {
        ZStack {
            item.kind.color.opacity(0.16)
            Image(systemName: item.kind.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(item.kind.color)
        }
    }
}

/// A tile as used in the notch strip and the library grid.
struct ClipTile: View {
    let item: ClipItem
    /// nil lets the tile stretch to fill its grid cell.
    var width: CGFloat? = 148
    var height: CGFloat = 108
    var selected: Bool = false
    /// When set, this tile belongs to a multi-selection and drags the whole set.
    var multiDrag: (() -> [ClipItem])? = nil
    /// When set, the tile shows a selection circle on hover that adds/removes it
    /// from the selection without replacing it — no modifier key needed.
    var onToggleSelect: (() -> Void)? = nil
    var onActivate: () -> Void
    var onDoubleActivate: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ClipPreview(item: item, compact: true,
                            reserveCorner: onToggleSelect != nil && !item.kind.isVisual)
                    .frame(maxWidth: .infinity)
                    .frame(height: height - 24)
                    .clipped()

                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(4)
                        .background(Circle().fill(Color.yellow))
                        .padding(5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height - 24)
            .background(Theme.panelRaised)

            HStack(spacing: 5) {
                AppBadge(bundleID: item.appBundleID, size: 11)
                Text(item.kind == .screenshot ? "Screenshot" : (item.appName.isEmpty ? item.kind.title : item.appName))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.relativeTime)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
        }
        .frame(maxWidth: width == nil ? .infinity : width, minHeight: height, maxHeight: height)
        .frame(width: width)
        .background(hovering || selected ? Theme.cardHover : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(selected ? Theme.accent : (hovering ? Theme.strokeStrong : Theme.stroke),
                              lineWidth: selected ? 1.6 : 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(item.kind.color)
                .frame(width: 3, height: 16)
                .padding(.top, 8)
                .opacity(showsCheckbox ? 0 : (hovering || selected ? 1 : 0.55))
        }
        .overlay(alignment: .topLeading) {
            if showsCheckbox {
                ZStack(alignment: .topLeading) {
                    // Images have no reserved corner, so darken behind the circle.
                    if item.kind.isVisual {
                        RadialGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0)],
                                       center: .topLeading, startRadius: 6, endRadius: 46)
                            .frame(width: 62, height: 62)
                            .allowsHitTesting(false)
                    }
                    selectionCircle
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .transition(.opacity)
            }
        }
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(Theme.quick, value: hovering)
        .stashHover($hovering)
        .modifier(TileInteraction(item: item, multiDrag: multiDrag,
                                  onActivate: onActivate, onDoubleActivate: onDoubleActivate))
        .contextMenu {
            ClipContextMenu(item: item, selection: multiDrag?() ?? [],
                            onActivate: onDoubleActivate ?? onActivate)
        }
        .help(item.title)
    }

    /// Visible once the pointer is over the tile, or whenever it is already picked.
    private var showsCheckbox: Bool {
        onToggleSelect != nil && (hovering || selected)
    }

    private var selectionCircle: some View {
        Button { onToggleSelect?() } label: {
            ZStack {
                Circle()
                    .fill(selected ? Theme.accent : Color.black.opacity(0.55))
                Circle()
                    .strokeBorder(selected ? Color.clear : Color.white.opacity(0.75), lineWidth: 1.5)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 19, height: 19)
        }
        .buttonStyle(.plain)
        .padding(7)
        .help(selected ? "Remove from selection" : "Add to selection")
    }
}

/// Clicking and dragging differ depending on whether the tile is part of a
/// multi-selection: one clip stays on SwiftUI's own drag, several hand off to an
/// AppKit dragging session.
private struct TileInteraction: ViewModifier {
    let item: ClipItem
    let multiDrag: (() -> [ClipItem])?
    let onActivate: () -> Void
    let onDoubleActivate: (() -> Void)?

    func body(content: Content) -> some View {
        if let multiDrag {
            content.overlay(MultiDragOverlay(items: multiDrag, onClick: onActivate))
        } else if let onDoubleActivate {
            content
                .onTapGesture(count: 2, perform: onDoubleActivate)
                .onTapGesture(count: 1, perform: onActivate)
                .onDrag { Paster.itemProvider(for: item) }
        } else {
            content
                .onTapGesture(perform: onActivate)
                .onDrag { Paster.itemProvider(for: item) }
        }
    }
}

/// A dense list row for quick search results.
struct ClipRow: View {
    let item: ClipItem
    var selected: Bool
    var onActivate: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.panelRaised)
                ClipThumb(item: item)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? item.preview.firstLine : item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(item.kind.title, systemImage: item.kind.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.kind.color)
                    if !item.appName.isEmpty {
                        Text("·").foregroundStyle(Theme.tertiary)
                        Text(item.appName).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Text("·").foregroundStyle(Theme.tertiary)
                    Text(item.relativeTime).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }
            if selected {
                Text("⏎")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.accentSoft : (hovering ? Theme.card : Color.clear))
        )
        .contentShape(Rectangle())
        .stashHover($hovering)
        .onTapGesture(perform: onActivate)
        .onDrag { Paster.itemProvider(for: item) }
        .contextMenu { ClipContextMenu(item: item, onActivate: onActivate) }
    }
}

struct ClipContextMenu: View {
    let item: ClipItem
    /// Non-empty when several clips are selected; actions then apply to all of them.
    var selection: [ClipItem] = []
    var onActivate: () -> Void
    @ObservedObject private var store = ClipStore.shared

    private var targets: [ClipItem] { selection.count > 1 ? selection : [item] }

    var body: some View {
        if targets.count > 1 {
            Button("Copy \(targets.count) Clips") { Paster.copyToPasteboard(targets) }
            Divider()
            Button("Pin All") { for t in targets where !t.pinned { store.togglePin(t) } }
            Button("Unpin All") { for t in targets where t.pinned { store.togglePin(t) } }
            Menu("Add All to Category") {
                ForEach(store.categories) { cat in
                    Button(cat.name) {
                        for t in targets {
                            store.setCategories(Array(Set(t.categoryIDs + [cat.id])), for: t)
                        }
                    }
                }
            }
            Divider()
            Button("Delete \(targets.count) Clips", role: .destructive) {
                for t in targets { store.delete(t) }
            }
        } else {
            singleItemMenu
        }
    }

    @ViewBuilder
    private var singleItemMenu: some View {
        Button("Paste", action: onActivate)
        Button("Copy") { Paster.copyToPasteboard(item) }
        if item.kind == .richText {
            Button("Paste as Plain Text") { Paster.pasteAsPlainText(item) }
        }
        if item.kind == .link, let t = item.text, let url = URL(string: t.trimmed) {
            Button("Open Link") { NSWorkspace.shared.open(url) }
        }
        if let path = item.blobPath ?? item.fileURLs.first {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        Divider()
        Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
        Menu("Add to Category") {
            ForEach(store.categories) { cat in
                Button {
                    var ids = Set(item.categoryIDs)
                    if ids.contains(cat.id) { ids.remove(cat.id) } else { ids.insert(cat.id) }
                    store.setCategories(Array(ids), for: item)
                } label: {
                    if item.categoryIDs.contains(cat.id) {
                        Label(cat.name, systemImage: "checkmark")
                    } else {
                        Text(cat.name)
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(item) }
    }
}
