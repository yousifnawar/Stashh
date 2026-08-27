#!/usr/bin/env swift
// Renders the icon at every size the App Store asset catalogue expects.
import AppKit
import Foundation

func render(size: CGFloat) -> Data? {
    let s = size
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let body = NSBezierPath(roundedRect: rect, xRadius: s * 0.2237, yRadius: s * 0.2237)

    ctx.saveGState()
    body.addClip()
    let colors = [NSColor(srgbRed: 0.13, green: 0.15, blue: 0.22, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).cgColor] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    let notchW = s * 0.34, notchH = s * 0.085
    let notch = NSBezierPath(roundedRect: CGRect(x: (s - notchW) / 2, y: s - inset - notchH,
                                                 width: notchW, height: notchH * 2),
                             xRadius: notchH * 0.55, yRadius: notchH * 0.55)
    NSColor.black.setFill()
    notch.fill()

    let cardW = s * 0.46, cardH = s * 0.135, radius = s * 0.045
    let accent = NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1)
    for i in 0..<3 {
        let scale = 1.0 - CGFloat(i) * 0.13
        let w = cardW * scale
        let y = s * 0.235 + CGFloat(2 - i) * cardH * 1.28
        let r = CGRect(x: (s - w) / 2, y: y, width: w, height: cardH)
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        NSColor.white.withAlphaComponent(i == 0 ? 0.97 : (i == 1 ? 0.55 : 0.3)).setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        if i == 0 {
            let stripe = NSBezierPath(roundedRect: CGRect(x: r.minX + s * 0.035, y: r.minY + cardH * 0.28,
                                                          width: s * 0.022, height: cardH * 0.44),
                                      xRadius: s * 0.011, yRadius: s * 0.011)
            accent.setFill()
            stripe.fill()
        }
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let specs: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (size, scale) in specs {
    let pixels = CGFloat(size * scale)
    let name = scale == 2 ? "icon_\(size)x\(size)@2x.png" : "icon_\(size)x\(size).png"
    if let data = render(size: pixels) {
        try? data.write(to: out.appendingPathComponent(name))
    }
}
print("wrote appiconset images to \(out.path)")
