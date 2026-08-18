import Foundation
import AppKit

/// Polls the general pasteboard and turns every new payload into a ClipItem.
/// Polling is the only reliable mechanism macOS offers — there is no change callback.
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Set by the paste path so writing a clip back doesn't re-record it.
    private var suppressUntilChangeCount: Int = -1

    private init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Call right after writing to the pasteboard ourselves.
    func ignoreNextChange() {
        suppressUntilChangeCount = pasteboard.changeCount + 1
    }

    private func poll() {
        guard Settings.shared.captureEnabled else {
            lastChangeCount = pasteboard.changeCount
            return
        }
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if current <= suppressUntilChangeCount {
            suppressUntilChangeCount = -1
            return
        }
        // Password managers and similar mark their payloads as transient/concealed.
        let types = pasteboard.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) ||
           types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) ||
           types.contains(NSPasteboard.PasteboardType("com.agilebits.onepassword")) {
            return
        }

        var front = NSWorkspace.shared.frontmostApplication
        // A copy made while one of our own panels is up belongs to the app behind it.
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            front = Paster.previousApp ?? front
        }
        if Settings.shared.isIgnored(bundleID: front?.bundleIdentifier) { return }

        if let item = buildItem(app: front) {
            ClipStore.shared.add(item)
            NotificationCenter.default.post(name: .stashDidCapture, object: item)
            if Settings.shared.playSound { NSSound(named: "Tink")?.play() }
        }
    }

    // MARK: - Payload extraction

    private func buildItem(app: NSRunningApplication?) -> ClipItem? {
        var item = ClipItem()
        item.appName = app?.localizedName ?? ""
        item.appBundleID = app?.bundleIdentifier ?? ""

        // 1. File promises / file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return fileItem(urls: urls, base: item)
        }

        // 2. Images (screenshots, copied graphics)
        if let image = imageFromPasteboard() {
            return imageItem(image, base: item, app: app)
        }

        // 3. Web / plain URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first, url.scheme != nil, !url.isFileURL,
           pasteboard.string(forType: .string) == nil {
            item.kind = .link
            item.text = url.absoluteString
            item.preview = url.absoluteString
            item.title = Classifier.title(for: .link, text: url.absoluteString, fileURLs: [])
            item.contentHash = url.absoluteString.sha256
            return item
        }

        // 4. Text, optionally with styling alongside it
        guard let string = pasteboard.string(forType: .string), !string.trimmed.isEmpty else { return nil }

        var kind = Classifier.kindForText(string)
        let rtfData = pasteboard.data(forType: .rtf)
        if kind == .text, rtfData != nil { kind = .richText }

        item.kind = kind
        item.text = string
        item.preview = String(string.prefix(4000))
        item.title = Classifier.title(for: kind, text: string, fileURLs: [])
        item.byteSize = string.utf8.count
        item.contentHash = string.sha256
        if kind == .color { item.colorHex = Classifier.colorHex(from: string) }
        if let rtfData, let path = BlobStore.writeData(rtfData, id: item.id, ext: "rtf") {
            item.rtfPath = path
        }
        return item
    }

    private func imageFromPasteboard() -> NSImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let img = NSImage(data: data) { return img }
        }
        if let objs = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            return objs.first
        }
        return nil
    }

    private func imageItem(_ image: NSImage, base: ClipItem, app: NSRunningApplication?) -> ClipItem? {
        var item = base
        let fromCaptureUI = Classifier.isScreenshotSource(bundleID: app?.bundleIdentifier)
        item.kind = fromCaptureUI ? .screenshot : .image
        guard let written = BlobStore.writePNG(image, id: item.id) else { return nil }
        item.blobPath = written.path
        item.byteSize = written.bytes
        item.pixelWidth = Int(written.size.width)
        item.pixelHeight = Int(written.size.height)
        item.thumbPath = BlobStore.makeThumbnail(from: image, id: item.id)
        item.contentHash = (try? Data(contentsOf: URL(fileURLWithPath: written.path)).sha256) ?? item.id
        item.title = item.kind == .screenshot ? "Screenshot \(shortTime())" : "Image \(item.dimensionLabel)"
        item.preview = "\(item.dimensionLabel) · \(item.byteSizeLabel)"
        return item
    }

    private func fileItem(urls: [URL], base: ClipItem) -> ClipItem {
        var item = base
        item.kind = .file
        item.fileURLs = urls.map(\.path)

        // A single image file gets a real preview.
        if urls.count == 1, let url = urls.first {
            item.thumbPath = BlobStore.fileThumbnail(for: url, id: item.id)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            item.byteSize = (attrs?[.size] as? Int) ?? 0
        }
        item.title = Classifier.title(for: .file, text: "", fileURLs: item.fileURLs)
        item.preview = urls.map { $0.deletingLastPathComponent().path }.joined(separator: "\n")
        item.text = urls.map(\.path).joined(separator: "\n")
        item.contentHash = item.fileURLs.joined(separator: "|").sha256
        return item
    }

    private func shortTime() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
