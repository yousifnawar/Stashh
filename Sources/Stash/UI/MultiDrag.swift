import SwiftUI
import AppKit

/// SwiftUI's `.onDrag` can only vend a single item provider, which is fine for one
/// clip but cannot express "drag these five images". This overlay starts a real
/// AppKit dragging session with one dragging item per selected clip.
///
/// It is only installed on tiles that belong to a multi-selection, so single-clip
/// behaviour stays pure SwiftUI.
struct MultiDragOverlay: NSViewRepresentable {
    /// Evaluated at drag time so the selection is always current.
    var items: () -> [ClipItem]
    /// Called on a click that never turned into a drag.
    var onClick: () -> Void

    func makeNSView(context: Context) -> MultiDragView {
        let view = MultiDragView()
        view.itemsProvider = items
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: MultiDragView, context: Context) {
        view.itemsProvider = items
        view.onClick = onClick
    }
}

final class MultiDragView: NSView, NSDraggingSource {
    var itemsProvider: () -> [ClipItem] = { [] }
    var onClick: () -> Void = {}

    private var pressOrigin: NSPoint?
    private let dragThreshold: CGFloat = 4

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The selection circle is SwiftUI content drawn beneath this layer, so the
    /// corner it occupies has to fall through rather than start a drag.
    private let checkboxCorner = CGSize(width: 42, height: 42)

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let corner = CGRect(x: 0, y: bounds.height - checkboxCorner.height,
                            width: checkboxCorner.width, height: checkboxCorner.height)
        if corner.contains(local) { return nil }
        return super.hitTest(point)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        pressOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin else { return }
        let now = event.locationInWindow
        guard hypot(now.x - origin.x, now.y - origin.y) > dragThreshold else { return }
        pressOrigin = nil
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressOrigin != nil else { return }
        pressOrigin = nil
        onClick()
    }

    /// Right-click still belongs to the SwiftUI context menu installed above us.
    override func menu(for event: NSEvent) -> NSMenu? {
        superview?.menu(for: event) ?? super.menu(for: event)
    }

    // MARK: Dragging

    private func beginDrag(with event: NSEvent) {
        let clips = itemsProvider()
        guard !clips.isEmpty else { return }
        DragWatcher.shared.suppressUntilMouseUp()

        var draggingItems: [NSDraggingItem] = []
        for (i, clip) in clips.enumerated() {
            guard let writer = Paster.pasteboardWriter(for: clip) else { continue }
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let image = Paster.dragImage(for: clip)
            // Fan the stack out slightly so the count is obvious under the cursor.
            let offset = CGFloat(min(i, 4)) * 9
            let frame = CGRect(x: offset, y: -offset, width: image.size.width, height: image.size.height)
            draggingItem.setDraggingFrame(frame, contents: image)
            draggingItems.append(draggingItem)
        }
        guard !draggingItems.isEmpty else { return }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        guard operation != [] else { return }
        for clip in itemsProvider() { ClipStore.shared.markUsed(clip) }
    }
}
