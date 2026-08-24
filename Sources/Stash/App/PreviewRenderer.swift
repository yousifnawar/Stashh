import SwiftUI
import AppKit

/// `Stash --render-preview <dir>` renders the main surfaces to PNGs offscreen.
/// Handy for checking layout without taking over the screen.
@MainActor
enum PreviewRenderer {

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--render-preview") else { return false }
        let dir = args.count > idx + 1 ? args[idx + 1] : NSTemporaryDirectory()
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Sandbox the whole run: sample content must not land in the real library.
        Paths.overrideRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stash-preview-\(UUID().uuidString)", isDirectory: true)

        seedIfEmpty()

        let notch = NotchController.shared
        notch.metrics = NotchGeometry.metrics()
        notch.state = .expanded
        render(NotchShellView(controller: notch)
                .frame(width: NotchGeometry.windowSize.width, height: NotchGeometry.windowSize.height)
                .background(Color(nsColor: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1))),
               size: NotchGeometry.windowSize, to: out.appendingPathComponent("notch-expanded.png"))

        render(NotchShellView(controller: notch, preselect: 3)
                .frame(width: NotchGeometry.windowSize.width, height: NotchGeometry.windowSize.height)
                .background(Color(nsColor: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1))),
               size: NotchGeometry.windowSize,
               to: out.appendingPathComponent("notch-selection.png"))

        seedShelf()

        notch.state = .dropZone
        render(NotchShellView(controller: notch)
                .frame(width: NotchGeometry.windowSize.width, height: NotchGeometry.windowSize.height)
                .background(Color(nsColor: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1))),
               size: NotchGeometry.windowSize,
               to: out.appendingPathComponent("notch-dropzone.png"))

        notch.state = .expanded
        render(NotchShellView(controller: notch, startTab: .shelf)
                .frame(width: NotchGeometry.windowSize.width, height: NotchGeometry.windowSize.height)
                .background(Color(nsColor: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1))),
               size: NotchGeometry.windowSize,
               to: out.appendingPathComponent("notch-shelf.png"))

        render(LibraryView().frame(width: 1120, height: 720),
               size: CGSize(width: 1120, height: 720),
               to: out.appendingPathComponent("library.png"))

        render(LibraryView(preselect: 1).frame(width: 1120, height: 720),
               size: CGSize(width: 1120, height: 720),
               to: out.appendingPathComponent("library-oneselected.png"))

        render(LibraryView(preselect: 4).frame(width: 1120, height: 720),
               size: CGSize(width: 1120, height: 720),
               to: out.appendingPathComponent("library-multiselect.png"))

        let qs = QuickSearchController.shared
        qs.query = ""
        render(QuickSearchView(controller: qs).frame(width: 660, height: 460).padding(20)
                .background(Color(nsColor: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1))),
               size: CGSize(width: 700, height: 500),
               to: out.appendingPathComponent("quick-search.png"))

        render(SettingsView().frame(width: 480, height: 900),
               size: CGSize(width: 480, height: 900),
               to: out.appendingPathComponent("settings.png"))

        for i in 0..<8 {
            render(OnboardingView(startAt: i, onFinish: {}).frame(width: 720, height: 560),
                   size: CGSize(width: 720, height: 560),
                   to: out.appendingPathComponent("tutorial-\(i + 1).png"))
        }

        print("rendered previews to \(out.path)")
        return true
    }

    /// Renders through a real (offscreen) window so ScrollViews and AppKit-backed
    /// views lay out exactly as they do in the app.
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))

        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)

        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("failed to render \(url.lastPathComponent)")
            window.orderOut(nil)
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }

    /// A few parked files so the shelf preview isn't empty.
    private static func seedShelf() {
        guard ShelfStore.shared.isEmpty else { return }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stash-shelf-seed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var urls: [URL] = []
        for name in ["Contract v3.pdf", "Budget.numbers", "notes.md"] {
            let url = dir.appendingPathComponent(name)
            try? Data("sample".utf8).write(to: url)
            urls.append(url)
        }
        let shot = dir.appendingPathComponent("Mockup.png")
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(srgbRed: 0.42, green: 0.55, blue: 0.95, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 300, height: 200).fill()
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSRect(x: 40, y: 120, width: 220, height: 40).fill()
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: shot)
            urls.insert(shot, at: 0)
        }
        ShelfStore.shared.add(urls: urls)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    }

    /// Sample content so previews aren't empty on a fresh install.
    private static func seedIfEmpty() {
        // Kick off the store's initial read and let it land before deciding it is empty.
        _ = ClipStore.shared
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard ClipStore.shared.items.count < 6 else { return }
        let samples: [(ItemKind, String, String, String)] = [
            (.link, "figma.com/file/Nx8/Design-System", "https://figma.com/file/Nx8/Design-System", "Safari"),
            (.code, "const theme = createTheme({", "const theme = createTheme({\n  radius: 12,\n  accent: \"#5B8CFF\",\n  spacing: [4, 8, 12, 16]\n})", "VS Code"),
            (.color, "#5B8CFF", "#5B8CFF", "Figma"),
            (.text, "Ship the notch shell first, then the library.", "Ship the notch shell first, then the library.", "Notes"),
            (.text, "yousif@example.com", "yousif@example.com", "Mail"),
            (.code, "git rebase -i origin/main", "git rebase -i origin/main", "Terminal"),
            (.link, "developer.apple.com/documentation/appkit", "https://developer.apple.com/documentation/appkit", "Safari"),
            (.text, "Invoice #2291 — due 30 Aug", "Invoice #2291 — due 30 Aug", "Numbers")
        ]
        for (i, s) in samples.enumerated() {
            var item = ClipItem()
            item.kind = s.0
            item.title = s.1
            item.text = s.2
            item.preview = s.2
            item.appName = s.3
            item.createdAt = Date().addingTimeInterval(-Double(i) * 900)
            item.contentHash = s.2.sha256
            if s.0 == .color { item.colorHex = s.2 }
            if i == 0 { item.pinned = true }
            ClipStore.shared.add(item)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    }
}
