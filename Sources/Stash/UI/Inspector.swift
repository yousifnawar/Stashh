import SwiftUI
import AppKit

/// Right-hand detail pane in the library: full preview, metadata, tags, categories.
struct InspectorView: View {
    let item: ClipItem
    var onClose: () -> Void

    @ObservedObject private var store = ClipStore.shared
    @State private var titleDraft: String = ""
    @State private var tagDraft: String = ""

    private var live: ClipItem { store.items.first { $0.id == item.id } ?? item }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(live.kind.title, systemImage: live.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(live.kind.color)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview

                    TextField("Title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .onSubmit { store.rename(live, to: titleDraft) }

                    metadata

                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12)).foregroundStyle(Theme.accent)
                        Text("Hover another clip and click its circle to select both, then drag them out together.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft.opacity(0.5)))

                    // Categories
                    VStack(alignment: .leading, spacing: 7) {
                        Text("CATEGORIES")
                            .font(.system(size: 9.5, weight: .bold)).tracking(0.6)
                            .foregroundStyle(Theme.tertiary)
                        FlowLayout(spacing: 6) {
                            ForEach(store.categories) { cat in
                                let on = live.categoryIDs.contains(cat.id)
                                FilterChip(title: cat.name, symbol: cat.symbol,
                                           active: on, tint: Color(hex: cat.colorHex)) {
                                    var ids = Set(live.categoryIDs)
                                    if on { ids.remove(cat.id) } else { ids.insert(cat.id) }
                                    store.setCategories(Array(ids), for: live)
                                }
                            }
                        }
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 7) {
                        Text("TAGS")
                            .font(.system(size: 9.5, weight: .bold)).tracking(0.6)
                            .foregroundStyle(Theme.tertiary)
                        FlowLayout(spacing: 6) {
                            ForEach(live.tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text("#\(tag)").font(.system(size: 10.5))
                                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                                }
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                                .onTapGesture {
                                    store.setTags(live.tags.filter { $0 != tag }, for: live)
                                }
                            }
                        }
                        TextField("Add tag…", text: $tagDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                            .onSubmit {
                                let t = tagDraft.trimmed.replacingOccurrences(of: "#", with: "")
                                guard !t.isEmpty else { return }
                                store.setTags(Array(Set(live.tags + [t])).sorted(), for: live)
                                tagDraft = ""
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }

            Divider().overlay(Theme.stroke)
            actions
        }
        .background(Color.black.opacity(0.18))
        .onAppear { titleDraft = live.title }
        .onChange(of: item.id) { _, _ in titleDraft = live.title }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panelRaised)
            ClipPreview(item: live)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(height: live.kind.isVisual ? 180 : 150)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.stroke, lineWidth: 1))
        .onDrag { Paster.itemProvider(for: live) }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetaRow(label: "Source") {
                HStack(spacing: 5) {
                    AppBadge(bundleID: live.appBundleID, size: 13)
                    Text(live.appName.isEmpty ? "Unknown" : live.appName)
                }
            }
            MetaRow(label: "Copied") { Text(fullDate(live.createdAt)) }
            if live.useCount > 0 {
                MetaRow(label: "Pasted") { Text("\(live.useCount)×") }
            }
            if !live.dimensionLabel.isEmpty {
                MetaRow(label: "Size") { Text(live.dimensionLabel) }
            }
            if !live.byteSizeLabel.isEmpty {
                MetaRow(label: "Weight") { Text(live.byteSizeLabel) }
            }
            if let t = live.text, live.kind != .file {
                MetaRow(label: "Length") { Text("\(t.count) chars") }
            }
            if !live.fileURLs.isEmpty {
                MetaRow(label: "Path") {
                    Text(live.fileURLs[0]).lineLimit(2).truncationMode(.middle)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                Paster.paste(live)
            } label: {
                Label("Paste", systemImage: "arrow.down.doc")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button { Paster.copyToPasteboard(live) } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 11.5))
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Copy")

            Button { store.togglePin(live) } label: {
                Image(systemName: live.pinned ? "pin.slash" : "pin")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(SecondaryButtonStyle())
            .help(live.pinned ? "Unpin" : "Pin")

            Button {
                store.delete(live)
                onClose()
            } label: {
                Image(systemName: "trash").font(.system(size: 11.5))
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Delete")
        }
        .padding(12)
    }

    private func fullDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}

struct MetaRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 54, alignment: .leading)
            content
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.secondary)
            .frame(width: 30, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.07)))
    }
}

/// Wrapping stack for chips — SwiftUI still has no built-in flow layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 260
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Shown instead of the single-clip inspector when several clips are selected.
struct MultiSelectionInspector: View {
    let items: [ClipItem]
    var onClose: () -> Void

    @ObservedObject private var store = ClipStore.shared

    private var kindTally: [(ItemKind, Int)] {
        var counts: [ItemKind: Int] = [:]
        for item in items { counts[item.kind, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var totalBytes: Int { items.reduce(0) { $0 + $1.byteSize } }
    private var allPinned: Bool { items.allSatisfy(\.pinned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(items.count) clips selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stack

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(kindTally, id: \.0) { kind, count in
                            MetaRow(label: kind.title) { Text("\(count)") }
                        }
                        if totalBytes > 0 {
                            MetaRow(label: "Total") {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(totalBytes),
                                                               countStyle: .file))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("ADD ALL TO")
                            .font(.system(size: 9.5, weight: .bold)).tracking(0.6)
                            .foregroundStyle(Theme.tertiary)
                        FlowLayout(spacing: 6) {
                            ForEach(store.categories) { cat in
                                FilterChip(title: cat.name, symbol: cat.symbol,
                                           active: false, tint: Color(hex: cat.colorHex)) {
                                    for item in items {
                                        store.setCategories(Array(Set(item.categoryIDs + [cat.id])), for: item)
                                    }
                                }
                            }
                        }
                    }

                    Text("Drag any of the selected tiles to move all \(items.count) into another app at once.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }

            Divider().overlay(Theme.stroke)
            HStack(spacing: 8) {
                Button {
                    Paster.copyToPasteboard(items)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    for item in items where item.pinned == allPinned { store.togglePin(item) }
                } label: {
                    Image(systemName: allPinned ? "pin.slash" : "pin").font(.system(size: 11.5))
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(allPinned ? "Unpin all" : "Pin all")

                Button {
                    for item in items { store.delete(item) }
                    onClose()
                } label: {
                    Image(systemName: "trash").font(.system(size: 11.5))
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("Delete all")
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.18))
    }

    /// A fanned stack of the first few selected clips.
    private var stack: some View {
        ZStack {
            ForEach(Array(items.prefix(4).enumerated().reversed()), id: \.element.id) { i, item in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panelRaised)
                    ClipThumb(item: item)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .frame(width: 120, height: 96)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1))
                .rotationEffect(.degrees(Double(i) * 4 - 6))
                .offset(x: CGFloat(i) * 14 - 20, y: CGFloat(i) * 4)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            }
            if items.count > 4 {
                Text("+\(items.count - 4)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent))
                    .offset(x: 74, y: 34)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }
}
