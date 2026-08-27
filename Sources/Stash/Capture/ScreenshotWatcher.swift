import Foundation
import AppKit

/// Watches the folder macOS drops screenshots into and pulls new captures into the
/// history even when they were never copied to the clipboard.
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1
    private var seen: Set<String> = []
    private var watchedURL: URL?
    private let queue = DispatchQueue(label: "com.nawar.stash.screenshots", qos: .utility)

    private init() {}

    static func screenshotFolder() -> URL? { ScreenshotFolder.resolve() }

    func start() {
        stop()
        guard Settings.shared.captureScreenshots else { return }
        guard let folder = Self.screenshotFolder() else {
            // Sandboxed and no folder chosen yet — Settings offers the picker.
            return
        }
        watchedURL = folder

        // Everything already on disk is "old" — we only want captures from now on.
        seen = Set(currentFiles(in: folder).map(\.path))

        fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[Stash] cannot watch \(folder.path) — grant Files & Folders access")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    func restart() { start() }

    private func currentFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let all = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return all.filter { ["png", "jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }
    }

    private func scan() {
        guard let folder = watchedURL, Settings.shared.captureScreenshots else { return }
        let files = currentFiles(in: folder)
        let fresh = files.filter { !seen.contains($0.path) && looksLikeScreenshot($0) }
        seen.formUnion(files.map(\.path))
        for url in fresh {
            // The file is still being written when the event fires.
            queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.ingest(url) }
        }
    }

    /// macOS names captures "Screenshot 2026-08-19 at 10.14.02.png" (localised), and
    /// screen recordings similarly. Match the localised prefix plus the date shape.
    private func looksLikeScreenshot(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        if name.range(of: #"\d{4}-\d{2}-\d{2} at \d"#, options: .regularExpression) != nil { return true }
        let lower = name.lowercased()
        return lower.hasPrefix("screenshot") || lower.hasPrefix("screen shot")
    }

    private func ingest(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        var item = ClipItem()
        item.kind = .screenshot
        item.appName = "Screenshot"
        item.appBundleID = "com.apple.screencaptureui"
        item.fileURLs = [url.path]

        guard let written = BlobStore.writePNG(image, id: item.id) else { return }
        item.blobPath = written.path
        item.byteSize = written.bytes
        item.pixelWidth = Int(written.size.width)
        item.pixelHeight = Int(written.size.height)
        item.thumbPath = BlobStore.makeThumbnail(from: image, id: item.id)
        item.contentHash = (try? Data(contentsOf: url).sha256) ?? item.id
        item.title = url.deletingPathExtension().lastPathComponent
        item.preview = "\(item.dimensionLabel) · \(item.byteSizeLabel)"

        DispatchQueue.main.async {
            ClipStore.shared.add(item)
            NotificationCenter.default.post(name: .stashDidCapture, object: item)
        }
    }
}
