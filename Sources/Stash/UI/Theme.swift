import SwiftUI
import AppKit

enum Theme {
    // Surfaces
    static let notchBackground = Color.black
    static let panel = Color(nsColor: NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 1))
    static let panelRaised = Color(nsColor: NSColor(srgbRed: 0.11, green: 0.115, blue: 0.135, alpha: 1))
    static let card = Color.white.opacity(0.06)
    static let cardHover = Color.white.opacity(0.11)
    static let stroke = Color.white.opacity(0.09)
    static let strokeStrong = Color.white.opacity(0.18)

    // Text
    static let primary = Color.white.opacity(0.95)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)

    static let accent = Color(nsColor: NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1))
    static let accentSoft = Color(nsColor: NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 0.22))

    // Motion
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.85)

    // Metrics
    static let cardRadius: CGFloat = 12
    static let notchCornerRadius: CGFloat = 22
}

extension Color {
    init(hex: String) {
        self = Color(nsColor: NSColor(hex: hex) ?? .systemBlue)
    }
}

extension ItemKind {
    var color: Color { Color(nsColor: accent) }
}

/// Rounded rect with only the bottom corners curved — the notch's own shape.
struct BottomRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The little inward curve where the panel meets the menu bar, so the shell reads
/// as one continuous piece of hardware rather than a floating rectangle.
struct NotchFlare: View {
    var size: CGFloat = 12
    var flipped: Bool = false
    var body: some View {
        Path { p in
            if flipped {
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: size))
                p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: size, y: 0))
            } else {
                p.move(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 0, y: size))
                p.addQuadCurve(to: CGPoint(x: size, y: 0), control: CGPoint(x: 0, y: 0))
            }
        }
        .fill(Color.black)
        .frame(width: size, height: size)
    }
}

struct HoverScale: ViewModifier {
    @State private var hovering = false
    var scale: CGFloat = 1.04
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(Theme.quick, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverScale(_ s: CGFloat = 1.04) -> some View { modifier(HoverScale(scale: s)) }

    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

/// App icon for a bundle id, cached so grids don't hit the workspace repeatedly.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if bundleID.isEmpty { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        cache[bundleID] = img
        return img
    }
}

struct AppBadge: View {
    let bundleID: String
    var size: CGFloat = 14
    var body: some View {
        if let icon = AppIcons.icon(for: bundleID) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.8))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
