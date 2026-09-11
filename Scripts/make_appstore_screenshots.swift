#!/usr/bin/env swift
// Composes Mac App Store screenshots at 2880×1800 (16:10, an accepted size)
// from the offscreen renders in docs/.
import AppKit
import Foundation

let W: CGFloat = 2880, H: CGFloat = 1800
let shots: [(file: String, title: String, subtitle: String)] = [
    ("notch-expanded.png", "Your clipboard, in the notch", "Hover the notch to see everything you copied. Click to paste it back."),
    ("quick-search.png",   "Find anything in seconds",     "Type a few letters and press Return."),
    ("library.png",        "Sorted for you",               "Grouped by type, by app and by your own categories."),
    ("notch-shelf.png",    "Park files on the shelf",      "Drag a file to the top of the screen. Pick it up later."),
    ("notch-selection.png","Move many at once",            "Select several clips and drag them out together."),
]

/// Renders sit on a flat background wider and taller than the UI itself. Crop to
/// the bounding box of everything that isn't that background.
func trimmed(_ image: NSImage) -> CGImage? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
    let w = cg.width, h = cg.height, bpp = cg.bitsPerPixel / 8, row = cg.bytesPerRow
    func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let o = y * row + x * bpp
        return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]))
    }
    let bg = px(2, h - 3)
    func isBackground(_ x: Int, _ y: Int) -> Bool {
        let c = px(x, y)
        return abs(c.0 - bg.0) < 8 && abs(c.1 - bg.1) < 8 && abs(c.2 - bg.2) < 8
    }
    var minX = w, minY = h, maxX = 0, maxY = 0
    let step = 3
    for y in stride(from: 0, to: h, by: step) {
        for x in stride(from: 0, to: w, by: step) where !isBackground(x, y) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX > minX, maxY > minY else { return cg }
    let pad = 4
    let rect = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                      width: min(w, maxX + pad) - max(0, minX - pad),
                      height: min(h, maxY + pad) - max(0, minY - pad))
    return cg.cropping(to: rect)
}

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: style]
    NSString(string: text).draw(in: CGRect(x: 160, y: y, width: W - 320, height: size * 1.4),
                                withAttributes: attrs)
}

for (index, shot) in shots.enumerated() {
    guard let original = NSImage(contentsOfFile: "docs/\(shot.file)"),
          let cropped = trimmed(original) else {
        print("missing docs/\(shot.file)"); continue
    }
    let srcW = CGFloat(cropped.width), srcH = CGFloat(cropped.height)
    let source = NSImage(cgImage: cropped, size: NSSize(width: srcW, height: srcH))

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.11, green: 0.13, blue: 0.22, alpha: 1).cgColor,
        NSColor(srgbRed: 0.03, green: 0.035, blue: 0.06, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    draw(shot.title, size: 118, weight: .bold, color: .white, y: H - 300)
    draw(shot.subtitle, size: 54, weight: .regular, color: NSColor.white.withAlphaComponent(0.62), y: H - 420)

    // Fit the render into the area under the caption, with generous margins.
    let boxW = W - 440, boxH = H - 620
    let scale = min(boxW / srcW, boxH / srcH)
    let w = srcW * scale, h = srcH * scale
    let frame = CGRect(x: (W - w) / 2, y: (boxH - h) / 2 + 90, width: w, height: h)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 90,
                  color: NSColor.black.withAlphaComponent(0.6).cgColor)
    NSBezierPath(roundedRect: frame, xRadius: 36, yRadius: 36).addClip()
    source.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    let out = "AppStore/screenshots/\(index + 1)-\(shot.file)"
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
