import SwiftUI
import AppKit

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    private static let seenKey = "hasSeenTutorial"

    static var hasSeenTutorial: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    func show() {
        if window == nil { build() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        Self.hasSeenTutorial = true
        window?.close()
        window = nil
        if LibraryWindowController.shared.isVisible == false {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Dismissing with the red button counts as having seen it.
    func windowWillClose(_ notification: Notification) {
        Self.hasSeenTutorial = true
        window = nil
        DispatchQueue.main.async {
            if !LibraryWindowController.shared.isVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func build() {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "How Stash Works"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 1)
        w.delegate = self
        w.contentView = NSHostingView(rootView: OnboardingView { [weak self] in self?.close() })
        window = w
    }
}

// MARK: - Content

private struct Page: Identifiable {
    let id = UUID()
    var eyebrow: String
    var title: String
    var body: String
    var accent: Color
    var art: Art

    enum Art { case welcome, notch, search, library, organize, shortcuts, permissions }
}

struct OnboardingView: View {
    var onFinish: () -> Void

    init(startAt: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _index = State(initialValue: startAt)
    }

    @State private var index: Int
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var shortcuts = Shortcuts.shared
    @State private var accessibilityGranted = Permissions.hasAccessibility

    private var pages: [Page] {
        [
            Page(eyebrow: "Welcome",
                 title: "Everything you copy, kept",
                 body: "Stash sits quietly in the background and saves every copy you make — text, links, code, colours, images, files — plus every screenshot you take. Nothing leaves your Mac.",
                 accent: Theme.accent, art: .welcome),

            Page(eyebrow: "The notch",
                 title: "Hover the notch, get your clips",
                 body: "Move your pointer onto the notch at the top of the screen and your recent clips slide out of it. Move away and it disappears again. Click a tile to paste it, or drag it straight into another app.\n\nPrefer the keyboard? \(key(.notch)) opens it, and \(key(.notch)) closes it. If you'd rather it never opened on its own, turn hovering off in Settings.",
                 accent: Theme.accent, art: .notch),

            Page(eyebrow: "Quick search",
                 title: "\(key(.quickSearch)) finds anything in seconds",
                 body: "Press \(key(.quickSearch)) anywhere, type a few characters, and press ⏎ — the clip is pasted straight into whatever you were working in. ↑↓ moves, ⇧⏎ copies without pasting, ⇥ cycles the filters.",
                 accent: Color(nsColor: ItemKind.link.accent), art: .search),

            Page(eyebrow: "Library",
                 title: "\(key(.library)) opens the whole history",
                 body: "The full window groups everything by type, by the app it came from, and by day. Pin what you reuse, tag what you want to find later, and make your own categories in the sidebar.",
                 accent: Color(nsColor: ItemKind.image.accent), art: .library),

            Page(eyebrow: "Organise",
                 title: "Pin, tag, drag, drop",
                 body: "Right-click any clip to pin it, file it into a category or delete it.\n\nHover any clip and a selection circle appears in its corner — in the notch and in the library. Click a few circles, then drag any one of them to take the whole set into another app. Dropping a pile of images onto the notch stashes them all in one go.",
                 accent: Color(nsColor: ItemKind.code.accent), art: .organize),

            Page(eyebrow: "Your keys, your rules",
                 title: "Change any shortcut you like",
                 body: "None of these are fixed. Click a shortcut below, press whatever combination suits you, and it takes effect immediately. Esc cancels, Delete removes a shortcut entirely, and every action stays reachable from the menu bar either way.\n\nYou can come back to this any time in Settings.",
                 accent: Color(nsColor: ItemKind.file.accent), art: .shortcuts),

            Page(eyebrow: "One last thing",
                 title: "Let Stash paste for you",
                 body: "Accessibility permission is what lets Stash press ⌘V in the app you were using. Without it Stash still works — it just puts the clip on your clipboard and you paste it yourself.",
                 accent: .orange, art: .permissions)
        ]
    }

    private func key(_ id: ShortcutID) -> String {
        let label = shortcuts.label(id)
        return label.isEmpty ? "the menu bar" : label
    }

    private var page: Page { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [page.accent.opacity(0.22), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                OnboardingArt(kind: page.art, accent: page.accent)
                    .padding(.horizontal, 40)
                    .padding(.top, 44)
                    .padding(.bottom, 24)
            }
            .frame(height: 268)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(page.eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold)).tracking(0.8)
                    .foregroundStyle(page.accent)
                Text(page.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text(page.body)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if page.art == .permissions { permissionControls }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 22)

            Spacer(minLength: 12)
            controls
        }
        .frame(width: 720, height: 560)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .animation(Theme.snappy, value: index)
        .onAppear { accessibilityGranted = Permissions.hasAccessibility }
    }

    private var permissionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if accessibilityGranted {
                    Label("Accessibility granted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Button("Open System Settings") {
                        Permissions.promptForAccessibilityOnce()
                        Permissions.openAccessibilitySettings()
                    }
                    Button("Re-check") { accessibilityGranted = Permissions.hasAccessibility }
                }
            }
            Toggle("Start Stash when I log in", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primary)
        }
        .padding(.top, 6)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .opacity(isLast ? 0 : 1)

            Spacer()

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? page.accent : Color.white.opacity(0.18))
                        .frame(width: i == index ? 18 : 6, height: 6)
                        .animation(Theme.quick, value: index)
                        .onTapGesture { index = i }
                }
            }

            Spacer()

            if index > 0 {
                Button("Back") { index -= 1 }
                    .buttonStyle(SecondaryPillStyle())
            }
            Button(isLast ? "Start using Stash" : "Next") {
                if isLast { onFinish() } else { index += 1 }
            }
            .buttonStyle(PrimaryPillStyle(tint: page.accent))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.2))
    }
}

// MARK: - Illustrations

/// Miniature mockups of each surface, drawn rather than shipped as assets so they
/// track the real UI's palette.
private struct OnboardingArt: View {
    let kind: Page.Art
    let accent: Color

    var body: some View {
        switch kind {
        case .welcome: welcome
        case .notch, .permissions: notch
        case .search: search
        case .library: library
        case .organize: organize
        case .shortcuts: shortcuts
        }
    }

    /// The live bindings, editable right here in the tutorial.
    private var shortcuts: some View {
        VStack(spacing: 10) {
            ForEach(ShortcutID.allCases) { id in
                HStack(spacing: 12) {
                    Image(systemName: id.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                        .frame(width: 16)
                    Text(id.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primary)
                    Spacer(minLength: 20)
                    ShortcutRecorder(id: id)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
        .frame(width: 460)
    }

    // A fanned stack of clip cards.
    private var welcome: some View {
        ZStack {
            ForEach(0..<4) { i in
                let k: [ItemKind] = [.screenshot, .color, .code, .link]
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.panelRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            Image(systemName: k[i].symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(nsColor: k[i].accent))
                            Text(k[i].title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                        }
                        .padding(12)
                    }
                    .frame(width: 190, height: 120)
                    .rotationEffect(.degrees(Double(i - 2) * 6))
                    .offset(x: CGFloat(i - 2) * 46, y: CGFloat(abs(i - 2)) * 8)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
            }
        }
    }

    // The notch with the shell hanging below it.
    private var notch: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 22)
                Capsule().fill(Color.black).frame(width: 110, height: 22)
            }
            .frame(width: 440)

            BottomRoundedShape(radius: 16)
                .fill(Color.black)
                .frame(width: 380, height: 116)
                .overlay(
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(0..<4) { i in
                                let k: [ItemKind] = [.link, .screenshot, .color, .code]
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                                    .overlay(
                                        Image(systemName: k[i].symbol)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color(nsColor: k[i].accent)))
                                    .frame(width: 78, height: 56)
                            }
                        }
                        HStack(spacing: 5) {
                            ForEach(["All", "Text", "Links"], id: \.self) { t in
                                Text(t)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(t == "All" ? .black : Theme.secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(t == "All" ? accent : Color.white.opacity(0.08)))
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                )
                .overlay(alignment: .top) {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 3)
                        .offset(x: 40, y: -26)
                }
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
        }
    }

    // The quick search panel.
    private var search: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                Text("design system")
                    .font(.system(size: 14)).foregroundStyle(Theme.primary)
                Spacer()
                Text("⌘⇧V")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.09)))
            }
            .padding(.horizontal, 16).frame(height: 44)
            Divider().overlay(Theme.stroke)

            VStack(spacing: 3) {
                ForEach(0..<3) { i in
                    let k: [ItemKind] = [.link, .code, .color]
                    let t = ["figma.com/file/Nx8/Design-System",
                             "const theme = createTheme({",
                             "#5B8CFF"]
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: k[i].accent).opacity(0.18))
                            .overlay(Image(systemName: k[i].symbol)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: k[i].accent)))
                            .frame(width: 30, height: 30)
                        Text(t[i]).font(.system(size: 11)).foregroundStyle(Theme.primary)
                            .lineLimit(1)
                        Spacer()
                        if i == 0 {
                            Text("⏎").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(i == 0 ? Theme.accentSoft : .clear))
                }
            }
            .padding(8)
        }
        .frame(width: 420)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    // The library window.
    private var library: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(["All Clips", "Pinned", "Links", "Screenshots", "Work"], id: \.self) { t in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(t == "All Clips" ? accent : Color.white.opacity(0.25))
                            .frame(width: 9, height: 9)
                        Text(t).font(.system(size: 9.5))
                            .foregroundStyle(t == "All Clips" ? Theme.primary : Theme.secondary)
                        Spacer()
                    }
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 120)
            .background(Color.black.opacity(0.25))

            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY").font(.system(size: 8, weight: .bold))
                    .tracking(0.6).foregroundStyle(Theme.tertiary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    ForEach(0..<6) { i in
                        let k: [ItemKind] = [.screenshot, .color, .code, .link, .text, .image]
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Image(systemName: k[i].symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(nsColor: k[i].accent)))
                            .frame(height: 50)
                    }
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(width: 440, height: 200)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
    }

    // A card being dragged out.
    private var organize: some View {
        HStack(spacing: 34) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.panelRaised)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(nsColor: ItemKind.image.accent))
                        Text("Screenshot").font(.system(size: 9))
                            .foregroundStyle(Theme.secondary)
                    })
                .frame(width: 130, height: 96)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
                        .padding(4).background(Circle().fill(.yellow)).padding(6)
                }
                .rotationEffect(.degrees(-7))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 8)

            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.tertiary)

            VStack(spacing: 7) {
                ForEach(["Work", "Snippets", "Design"], id: \.self) { t in
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10)).foregroundStyle(accent)
                        Text(t).font(.system(size: 11)).foregroundStyle(Theme.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(width: 150)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                }
            }
        }
    }
}

// MARK: - Buttons

struct PrimaryPillStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.black.opacity(0.88))
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.72 : 1)))
    }
}

struct SecondaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
    }
}
