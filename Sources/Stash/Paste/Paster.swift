import Foundation
import AppKit
import Carbon.HIToolbox

/// Writes clips back onto the pasteboard and, when permitted, drives ⌘V into
/// whatever app the user was last in.
enum Paster {

    /// The app that was frontmost before one of our panels appeared.
    private(set) static var previousApp: NSRunningApplication?

    static func rememberFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
    }

    /// Puts the clip on the general pasteboard in every representation it has.
    static func copyToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        ClipboardMonitor.shared.ignoreNextChange()
        pb.clearContents()

        switch item.kind {
        case .image, .screenshot:
            if let path = item.blobPath, let img = NSImage(contentsOfFile: path) {
                pb.writeObjects([img])
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    pb.setData(data, forType: .png)
                }
            }
        case .file:
            let urls = item.fileURLs.map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty { pb.writeObjects(urls) }
            if let t = item.text { pb.setString(t, forType: .string) }
        case .richText:
            if let rtfPath = item.rtfPath, let data = try? Data(contentsOf: URL(fileURLWithPath: rtfPath)) {
                pb.setData(data, forType: .rtf)
            }
            if let t = item.text { pb.setString(t, forType: .string) }
        default:
            if let t = item.text { pb.setString(t, forType: .string) }
        }

        ClipStore.shared.markUsed(item)
    }

    /// Copy, restore focus, then synthesise ⌘V.
    ///
    /// The App Store build stops after restoring focus: `CGEvent.post` is
    /// unavailable to sandboxed apps, and App Review rejects it under 2.4.5 as a
    /// non-accessibility use of an accessibility API. The clip is on the
    /// clipboard and the right app is frontmost, so ⌘V is one keystroke away.
    static func paste(_ item: ClipItem, restoreFocus: Bool = true) {
        copyToPasteboard(item)

        let app = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if restoreFocus, let app, !app.isActive { app.activate() }

            #if !APPSTORE
            guard Settings.shared.pasteDirectly else { return }
            guard Permissions.hasAccessibility else {
                Permissions.promptForAccessibilityOnce()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { sendCommandV() }
            #endif
        }
    }

    /// Plain-text paste that strips any styling.
    static func pasteAsPlainText(_ item: ClipItem) {
        var stripped = item
        stripped.rtfPath = nil
        if stripped.kind == .richText { stripped.kind = .text }
        paste(stripped)
    }

    #if !APPSTORE
    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)

        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
    #endif

    /// One pasteboard object per clip — the unit AppKit drags in a multi-item session.
    static func pasteboardWriter(for item: ClipItem) -> NSPasteboardWriting? {
        switch item.kind {
        case .image, .screenshot:
            if let path = item.blobPath { return URL(fileURLWithPath: path) as NSURL }
        case .file:
            if let staged = item.blobPath, FileManager.default.fileExists(atPath: staged) {
                return URL(fileURLWithPath: staged) as NSURL
            }
            if let path = item.fileURLs.first { return URL(fileURLWithPath: path) as NSURL }
        default:
            break
        }
        if let text = item.text, !text.isEmpty { return text as NSString }
        return item.preview as NSString
    }

    /// The thumbnail shown under the cursor while dragging.
    static func dragImage(for item: ClipItem, edge: CGFloat = 72) -> NSImage {
        if let thumb = item.thumbnail {
            let copy = NSImage(size: NSSize(width: edge, height: edge))
            copy.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            thumb.draw(in: NSRect(x: 0, y: 0, width: edge, height: edge),
                       from: .zero, operation: .sourceOver, fraction: 1)
            copy.unlockFocus()
            return copy
        }
        let image = NSImage(size: NSSize(width: edge, height: edge))
        image.lockFocus()
        NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: edge, height: edge),
                     xRadius: 10, yRadius: 10).fill()
        if let symbol = NSImage(systemSymbolName: item.kind.symbol, accessibilityDescription: nil) {
            symbol.isTemplate = true
            let tinted = NSImage(size: NSSize(width: 26, height: 26))
            tinted.lockFocus()
            item.kind.accent.set()
            NSRect(x: 0, y: 0, width: 26, height: 26).fill(using: .sourceOver)
            symbol.draw(in: NSRect(x: 0, y: 0, width: 26, height: 26),
                        from: .zero, operation: .destinationIn, fraction: 1)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: (edge - 26) / 2, y: (edge - 26) / 2, width: 26, height: 26))
        }
        image.unlockFocus()
        return image
    }

    /// Puts a whole selection on the pasteboard in one go.
    static func copyToPasteboard(_ items: [ClipItem]) {
        guard items.count > 1 else {
            if let one = items.first { copyToPasteboard(one) }
            return
        }
        let pb = NSPasteboard.general
        ClipboardMonitor.shared.ignoreNextChange()
        pb.clearContents()
        pb.writeObjects(items.compactMap { pasteboardWriter(for: $0) })
        for item in items { ClipStore.shared.markUsed(item) }
    }

    /// Item providers used for dragging clips out into other apps.
    static func itemProvider(for item: ClipItem) -> NSItemProvider {
        // Called exactly when a drag begins from our own UI.
        DragWatcher.shared.suppressUntilMouseUp()
        switch item.kind {
        case .image, .screenshot:
            if let path = item.blobPath {
                let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
                provider.suggestedName = item.title + ".png"
                return provider
            }
        case .file:
            let source = item.blobPath.map { URL(fileURLWithPath: $0) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? item.fileURLs.first.map { URL(fileURLWithPath: $0) }
            if let source, let provider = NSItemProvider(contentsOf: source) {
                return provider
            }
        default:
            break
        }
        return NSItemProvider(object: (item.text ?? item.preview) as NSString)
    }

    /// Accepts a whole drag at once. Items are added back-to-front so the first
    /// thing the user dropped ends up leftmost in the strip.
    @discardableResult
    static func ingestDropped(_ payloads: [DropIngest.Payload]) -> Int {
        var added = 0
        for payload in payloads.reversed() {
            switch payload {
            case .file(let url):
                ingestDroppedFiles([url])
            case .imageData(let data, let name):
                ingestDroppedImage(data, name: name)
            }
            added += 1
        }
        return added
    }

    /// An image with no file behind it — dragged out of a web page, say.
    private static func ingestDroppedImage(_ data: Data, name: String) {
        guard let image = NSImage(data: data) else { return }
        var item = ClipItem()
        item.kind = .image
        item.appName = "Drag & Drop"
        item.appBundleID = "com.nawar.stash.drop"
        guard let written = BlobStore.writePNG(image, id: item.id) else { return }
        item.blobPath = written.path
        item.pixelWidth = Int(written.size.width)
        item.pixelHeight = Int(written.size.height)
        item.byteSize = written.bytes
        item.thumbPath = BlobStore.makeThumbnail(from: image, id: item.id)
        item.contentHash = data.sha256
        item.title = (name as NSString).deletingPathExtension
        item.preview = "\(item.dimensionLabel) · \(item.byteSizeLabel)"
        ClipStore.shared.add(item)
    }

    /// Accepts clips dragged *into* Stash (files dropped on the notch).
    static func ingestDroppedFiles(_ urls: [URL]) {
        for url in urls.reversed() {
            var item = ClipItem()
            item.appName = "Drag & Drop"
            item.appBundleID = "com.nawar.stash.drop"
            item.fileURLs = [url.path]
            let isImage = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp"]
                .contains(url.pathExtension.lowercased())
            item.kind = isImage ? .image : .file
            if isImage, let img = NSImage(contentsOf: url), let written = BlobStore.writePNG(img, id: item.id) {
                item.blobPath = written.path
                item.pixelWidth = Int(written.size.width)
                item.pixelHeight = Int(written.size.height)
                item.byteSize = written.bytes
                item.thumbPath = BlobStore.makeThumbnail(from: img, id: item.id)
            } else {
                item.thumbPath = BlobStore.fileThumbnail(for: url, id: item.id)
                item.byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                item.text = url.path
            }
            item.title = url.lastPathComponent
            item.preview = url.deletingLastPathComponent().path
            item.contentHash = url.path.sha256
            ClipStore.shared.add(item)
        }
    }
}
