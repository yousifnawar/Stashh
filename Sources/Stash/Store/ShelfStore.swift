import Foundation
import AppKit
import Combine

/// A temporary parking space for files. Distinct from the clip history: things put
/// here are meant to be picked up again and dragged somewhere else, not archived.
///
/// Shelf entries reuse `ClipItem` so every existing tile, thumbnail, selection and
/// drag path works on them unchanged.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [ClipItem] = []

    private let queue = DispatchQueue(label: "com.nawar.stash.shelf", qos: .userInitiated)

    private init() {
        load()
    }

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Adding

    /// Parks files on the shelf. Returns how many were accepted.
    @discardableResult
    func add(urls: [URL]) -> Int {
        var accepted = 0
        for url in urls.reversed() where url.isFileURL {
            guard !items.contains(where: { $0.fileURLs.first == url.path }) else { continue }
            var item = ClipItem()
            item.kind = isImage(url) ? .image : .file
            item.appName = "Shelf"
            item.appBundleID = "com.nawar.stash.shelf"
            item.fileURLs = [url.path]
            item.title = url.lastPathComponent
            item.preview = url.deletingLastPathComponent().path
            item.contentHash = url.path.sha256
            item.byteSize = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

            items.insert(item, at: 0)
            accepted += 1
            stage(item, from: url)
        }
        if accepted > 0 { save() }
        return accepted
    }

    /// Also accepts raw image bytes, for drags out of a web page.
    @discardableResult
    func add(payloads: [DropIngest.Payload]) -> Int {
        var urls: [URL] = []
        var loose = 0
        for payload in payloads {
            switch payload {
            case .file(let url):
                urls.append(url)
            case .imageData(let data, let name):
                if let url = writeLooseImage(data, name: name) { urls.append(url); loose += 1 }
            }
        }
        return add(urls: urls)
    }

    /// Copies the file into Stash's own storage so the shelf survives the original
    /// being moved, renamed or deleted. A hard link is instant when the volume allows it.
    private func stage(_ item: ClipItem, from url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            let folder = Paths.shelf.appendingPathComponent(item.id, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(url.lastPathComponent)

            if !FileManager.default.fileExists(atPath: destination.path) {
                do { try FileManager.default.linkItem(at: url, to: destination) }
                catch { try? FileManager.default.copyItem(at: url, to: destination) }
            }
            let staged = FileManager.default.fileExists(atPath: destination.path)
            let thumb = BlobStore.fileThumbnail(for: staged ? destination : url, id: item.id)

            DispatchQueue.main.async {
                guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                if staged { self.items[index].blobPath = destination.path }
                self.items[index].thumbPath = thumb
                self.save()
            }
        }
    }

    private func writeLooseImage(_ data: Data, name: String) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let folder = Paths.shelf.appendingPathComponent("loose-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(base.isEmpty ? "image.png" : "\(base).png")
        do { try data.write(to: url); return url } catch { return nil }
    }

    private func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp"]
            .contains(url.pathExtension.lowercased())
    }

    // MARK: - Removing

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
        queue.async {
            try? FileManager.default.removeItem(
                at: Paths.shelf.appendingPathComponent(item.id, isDirectory: true))
            if let thumb = item.thumbPath { try? FileManager.default.removeItem(atPath: thumb) }
        }
    }

    func remove(_ toRemove: [ClipItem]) {
        for item in toRemove { remove(item) }
    }

    func clear() {
        let doomed = items
        items = []
        save()
        queue.async {
            for item in doomed {
                try? FileManager.default.removeItem(
                    at: Paths.shelf.appendingPathComponent(item.id, isDirectory: true))
                if let thumb = item.thumbPath { try? FileManager.default.removeItem(atPath: thumb) }
            }
        }
    }

    /// Promotes a parked file into the permanent clip history.
    func keepInHistory(_ item: ClipItem) {
        var copy = item
        copy.id = UUID().uuidString
        copy.appName = "Shelf"
        copy.createdAt = Date()
        ClipStore.shared.add(copy)
    }

    // MARK: - Where the file actually lives

    /// The staged copy when it exists, otherwise the original.
    static func url(for item: ClipItem) -> URL? {
        if let staged = item.blobPath, FileManager.default.fileExists(atPath: staged) {
            return URL(fileURLWithPath: staged)
        }
        if let original = item.fileURLs.first, FileManager.default.fileExists(atPath: original) {
            return URL(fileURLWithPath: original)
        }
        return nil
    }

    /// True when neither copy is on disk any more — shown as a dimmed tile.
    static func isMissing(_ item: ClipItem) -> Bool { url(for: item) == nil }

    // MARK: - Persistence

    private func save() {
        let snapshot = items
        queue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: Paths.shelfIndex)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Paths.shelfIndex),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        // Drop anything whose files vanished while Stash was closed.
        items = decoded.filter { !ShelfStore.isMissing($0) }
        if items.count != decoded.count { save() }
    }
}
