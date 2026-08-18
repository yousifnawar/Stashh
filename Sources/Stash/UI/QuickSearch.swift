import SwiftUI
import AppKit

/// Spotlight-style overlay: type, arrow, ⏎ pastes into the app you came from.
final class QuickSearchController: ObservableObject {
    static let shared = QuickSearchController()

    @Published var query: String = ""
    @Published var selection: Int = 0
    @Published var scope: Scope = .all

    private var panel: NSPanel?
    private var keyMonitor: Any?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        Paster.rememberFrontmostApp()
        NotchController.shared.collapse()
        query = ""
        selection = 0

        if panel == nil { build() }
        guard let panel else { return }

        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.midY - size.height / 2 + 90))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
        query = ""
        selection = 0
    }

    /// Paste and dismiss.
    func activate(_ item: ClipItem) {
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Paster.paste(item) }
    }

    var results: [ClipItem] {
        ClipStore.shared.search(query, scope: scope, limit: 200)
    }

    private func build() {
        let size = CGSize(width: 660, height: 460)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow

        let host = NSHostingView(rootView: QuickSearchView(controller: self))
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let results = self.results
            switch event.keyCode {
            case 53: // esc
                self.hide(); return nil
            case 125: // down
                if !results.isEmpty { self.selection = min(self.selection + 1, results.count - 1) }
                return nil
            case 126: // up
                self.selection = max(self.selection - 1, 0)
                return nil
            case 36, 76: // return
                if results.indices.contains(self.selection) {
                    if event.modifierFlags.contains(.shift) {
                        Paster.copyToPasteboard(results[self.selection])
                        self.hide()
                    } else {
                        self.activate(results[self.selection])
                    }
                }
                return nil
            case 48: // tab — cycle scope
                self.cycleScope(backwards: event.modifierFlags.contains(.shift))
                return nil
            default:
                // ⌘1…⌘9 pastes the nth result.
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers,
                   let n = Int(chars), n >= 1, n <= 9 {
                    if results.indices.contains(n - 1) { self.activate(results[n - 1]) }
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func cycleScope(backwards: Bool) {
        var scopes: [Scope] = [.all, .pinned]
        scopes += ItemKind.allCases.map { Scope.kind($0) }
        let idx = scopes.firstIndex(of: scope) ?? 0
        let next = backwards ? (idx - 1 + scopes.count) % scopes.count : (idx + 1) % scopes.count
        scope = scopes[next]
        selection = 0
    }
}

struct QuickSearchView: View {
    @ObservedObject var controller: QuickSearchController
    @ObservedObject private var store = ClipStore.shared
    @FocusState private var focused: Bool

    private var results: [ClipItem] { controller.results }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().overlay(Theme.stroke)
            scopeBar
            Divider().overlay(Theme.stroke)

            if results.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                                ClipRow(item: item, selected: idx == controller.selection) {
                                    controller.activate(item)
                                }
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: controller.selection) { _, new in
                        guard results.indices.contains(new) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(results[new].id, anchor: .center)
                        }
                    }
                }
            }

            Divider().overlay(Theme.stroke)
            hints
        }
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                Theme.panel.opacity(0.72)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.strokeStrong, lineWidth: 1)
        )
        .onAppear { focused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
            TextField("Search your clipboard…", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(Theme.primary)
                .focused($focused)
                .onChange(of: controller.query) { _, _ in controller.selection = 0 }
            if !controller.query.isEmpty {
                Button { controller.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                }.buttonStyle(.plain)
            }
            Text("\(results.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var scopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(title: "All", symbol: "square.grid.2x2",
                           active: controller.scope == .all, tint: Theme.accent) {
                    controller.scope = .all; controller.selection = 0
                }
                FilterChip(title: "Pinned", symbol: "pin.fill",
                           active: controller.scope == .pinned, tint: .yellow) {
                    controller.scope = .pinned; controller.selection = 0
                }
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    if store.count(for: .kind(kind)) > 0 {
                        FilterChip(title: kind.title, symbol: kind.symbol,
                                   active: controller.scope == .kind(kind), tint: kind.color) {
                            controller.scope = controller.scope == .kind(kind) ? .all : .kind(kind)
                            controller.selection = 0
                        }
                    }
                }
                ForEach(store.categories) { cat in
                    FilterChip(title: cat.name, symbol: cat.symbol,
                               active: controller.scope == .category(cat.id),
                               tint: Color(hex: cat.colorHex)) {
                        controller.scope = controller.scope == .category(cat.id) ? .all : .category(cat.id)
                        controller.selection = 0
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.tertiary)
            Text(controller.query.isEmpty ? "Nothing stashed yet" : "No matches for “\(controller.query)”")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hints: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "↑↓", label: "navigate")
            KeyHint(keys: "⏎", label: "paste")
            KeyHint(keys: "⇧⏎", label: "copy only")
            KeyHint(keys: "⇥", label: "filter")
            Spacer()
            KeyHint(keys: "esc", label: "close")
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}

struct KeyHint: View {
    let keys: String
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.09)))
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
