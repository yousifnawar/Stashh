import Foundation
import AppKit
import Combine

/// macOS offers no notification for "a drag started somewhere on the system", but
/// the drag pasteboard's change count ticks over the moment one begins. Watching
/// that, together with the mouse button state, is enough to know a drag is in
/// flight — and whether it is heading for the top of the screen.
final class DragWatcher: ObservableObject {
    static let shared = DragWatcher()

    /// A drag is in progress somewhere on the system.
    @Published private(set) var isDragging = false
    /// That drag has reached the top strip of the screen, where the notch lives.
    @Published private(set) var isNearTop = false

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastChangeCount = 0
    private var timer: Timer?
    /// Set while Stash itself is the drag source, so we don't offer to catch our own files.
    private var suppressed = false

    /// How far down from the top edge counts as "at the notch".
    private let topBand: CGFloat = 120

    private init() {}

    func start() {
        stop()
        lastChangeCount = dragPasteboard.changeCount
        let t = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reset()
    }

    /// Called when a drag begins from inside Stash.
    func suppressUntilMouseUp() {
        suppressed = true
        reset()
    }

    private func poll() {
        let mouseDown = NSEvent.pressedMouseButtons & 0x1 != 0

        if !mouseDown {
            // The button came up: any drag is over, and a new one may now begin.
            suppressed = false
            if isDragging { reset() }
            lastChangeCount = dragPasteboard.changeCount
            return
        }

        let count = dragPasteboard.changeCount
        if count != lastChangeCount {
            lastChangeCount = count
            if !suppressed, Settings.shared.shelfEnabled, dragCarriesFiles {
                isDragging = true
            }
        }

        guard isDragging else { return }
        let atTop = pointerIsNearTop
        if atTop != isNearTop { isNearTop = atTop }
    }

    /// Only react to drags that actually carry something we can hold.
    private var dragCarriesFiles: Bool {
        guard let types = dragPasteboard.types else { return false }
        return types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType("public.file-url"))
            || types.contains(.URL)
            || types.contains(.png)
            || types.contains(.tiff)
    }

    private var pointerIsNearTop: Bool {
        let screen = NotchGeometry.metrics().screen
        let location = NSEvent.mouseLocation
        guard screen.frame.contains(CGPoint(x: location.x, y: min(location.y, screen.frame.maxY - 1)))
        else { return false }
        return location.y >= screen.frame.maxY - topBand
    }

    private func reset() {
        if isDragging { isDragging = false }
        if isNearTop { isNearTop = false }
    }
}
