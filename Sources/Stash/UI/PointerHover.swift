import SwiftUI
import AppKit

/// The notch panel is deliberately non-activating, so AppKit tracking areas (and
/// therefore SwiftUI's `.onHover`) never fire while another app is frontmost.
/// We track the pointer ourselves and hand its position down the view tree.
private struct PointerLocationKey: EnvironmentKey {
    static let defaultValue: CGPoint? = nil
}

extension EnvironmentValues {
    var pointerLocation: CGPoint? {
        get { self[PointerLocationKey.self] }
        set { self[PointerLocationKey.self] = newValue }
    }
}

enum StashSpace {
    static let root = "stashRoot"
}

private struct PointerProbe: Equatable {
    var point: CGPoint?
    var frame: CGRect
}

private struct StashHoverModifier: ViewModifier {
    @Binding var hovering: Bool
    @Environment(\.pointerLocation) private var pointer

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                // Fallback for windows that do receive real hover events.
                if pointer == nil { hovering = inside }
            }
            .background(
                GeometryReader { geo in
                    let probe = PointerProbe(point: pointer, frame: geo.frame(in: .named(StashSpace.root)))
                    Color.clear
                        .onChange(of: probe) { _, new in
                            guard let p = new.point else {
                                if hovering { hovering = false }
                                return
                            }
                            let inside = new.frame.contains(p)
                            if inside != hovering { hovering = inside }
                        }
                }
            )
    }
}

extension View {
    /// Hover tracking that works in non-activating panels.
    func stashHover(_ hovering: Binding<Bool>) -> some View {
        modifier(StashHoverModifier(hovering: hovering))
    }
}
