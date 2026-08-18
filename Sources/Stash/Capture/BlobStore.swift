import Foundation
import AppKit
import UniformTypeIdentifiers

/// Writes image payloads to disk and makes the thumbnails the UI renders.
enum BlobStore {

    @discardableResult
    static func writePNG(_ image: NSImage, id: String) -> (path: String, bytes: Int, size: CGSize)? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = Paths.blobs.appendingPathComponent("\(id).png")
        do {
            try data.write(to: url)
            return (url.path, data.count, CGSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        } catch {
            NSLog("[Stash] blob write failed: \(error)")
            return nil
        }
    }

    static func writeData(_ data: Data, id: String, ext: String) -> String? {
        let url = Paths.blobs.appendingPathComponent("\(id).\(ext)")
        do { try data.write(to: url); return url.path } catch { return nil }
    }

    /// Downsamples to fit `maxEdge` and stores a JPEG next to the original.
    @discardableResult
    static func makeThumbnail(from image: NSImage, id: String, maxEdge: CGFloat = 640) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxEdge / max(w, h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))

        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        target.size = NSSize(width: tw, height: th)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: tw, height: th),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = target.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return nil }
        let url = Paths.thumbs.appendingPathComponent("\(id).jpg")
        do { try data.write(to: url); return url.path } catch { return nil }
    }

    /// A thumbnail for an arbitrary file, using QuickLook-quality icons as a fallback.
    static func fileThumbnail(for url: URL, id: String) -> String? {
        if let img = NSImage(contentsOf: url), img.size.width > 0 {
            return makeThumbnail(from: img, id: id, maxEdge: 480)
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 256, height: 256)
        return makeThumbnail(from: icon, id: id, maxEdge: 256)
    }
}
