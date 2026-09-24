import SwiftUI
import AppKit
import Combine

// MARK: - Geometry

enum NotchGeometry {
    /// Physical notch metrics for a screen, or a synthesised "virtual notch" on
    /// displays without one so the shell still has somewhere to live.
    struct Metrics {
        var notchSize: CGSize
        var hasRealNotch: Bool
        var screen: NSScreen
    }

    /// The shell lives on the **main display** — the one chosen in System
    /// Settings → Displays, which carries the menu bar and is always
    /// `NSScreen.screens.first`. If that display has a physical notch the shell
    /// wraps it; otherwise it draws a virtual one at the top centre.
    ///
    /// Deliberately not "whichever screen has a notch": with a laptop beside an
    /// external monitor set as main, that would pin Stash to the laptop.
    static func metrics() -> Metrics {
        let screen = NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            if width > 60 {
                return Metrics(notchSize: CGSize(width: width, height: height),
                               hasRealNotch: true, screen: screen)
            }
        }
        return Metrics(notchSize: CGSize(width: 190, height: 30), hasRealNotch: false, screen: screen)
    }

    static let windowSize = CGSize(width: 780, height: 360)
    static let expandedWidth: CGFloat = 760

    /// Header (which flanks the notch) + clip strip + filter row.
    static func expandedSize(notch: CGSize) -> CGSize {
        CGSize(width: expandedWidth, height: max(notch.height, 34) + 1 + 136 + 16 + 42)
    }

    static func dropZoneSize(notch: CGSize) -> CGSize {
        CGSize(width: max(notch.width + 420, 580), height: max(notch.height + 44, 80))
    }

}

enum NotchState: Equatable {
    case collapsed
    /// A drag is heading for the notch: show a target to drop files onto.
    case dropZone
    case expanded
}

// MARK: - Panel

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Blocks mouse events everywhere except the currently visible shell, so the
/// desktop behind the (much larger) window stays clickable.
final class GateView: NSView {
    /// In top-left origin coordinates, matching the SwiftUI layout.
    var activeRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let topLeft = CGPoint(x: local.x, y: bounds.height - local.y)
        guard activeRect.insetBy(dx: -1, dy: -1).contains(topLeft) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - Controller

final class NotchController: ObservableObject {
    static let shared = NotchController()

    @Published var state: NotchState = .collapsed
    @Published var metrics = NotchGeometry.metrics()
    @Published var pointer: CGPoint?
    @Published var isDropTargeted = false
    /// Keeps the shell open while a menu or drag is in flight.
    @Published var holdOpen = false
    /// Set when the shell was opened by its keyboard shortcut rather than by
    /// hovering — it then stays put until the shortcut is pressed again.
    @Published private(set) var openedByShortcut = false

    private var panel: NotchPanel?
    private var gate: GateView?
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeSystemDrags()
    }

    /// Opens a drop target when a file drag reaches the top of the screen, and
    /// puts it away again when the drag ends elsewhere.
    private func observeSystemDrags() {
        let watcher = DragWatcher.shared
        watcher.$isDragging
            .combineLatest(watcher.$isNearTop)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dragging, nearTop in
                guard let self, self.panel != nil else { return }
                if dragging && nearTop {
                    self.showDropZone()
                } else if self.state == .dropZone {
                    self.collapse()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func start() {
        // No on/off switch: with hover off the shell is invisible and click-through
        // until its shortcut is pressed, so an "off" state only ever broke the
        // shortcut. Hover, the shelf and the shortcut each have their own control.
        guard panel == nil else { return }
        defer {
            StashLog.write("notch panel started on \(metrics.screen.localizedName) frame=\(panel?.frame ?? .zero) realNotch=\(metrics.hasRealNotch)")
        }

        metrics = NotchGeometry.metrics()
        let size = NotchGeometry.windowSize
        let screen = metrics.screen
        let frame = CGRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        let panel = NotchPanel(contentRect: frame,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let gate = GateView(frame: CGRect(origin: .zero, size: size))
        gate.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: NotchShellView(controller: self))
        hosting.frame = gate.bounds
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
        gate.addSubview(hosting)

        panel.contentView = gate
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.gate = gate
        updateGate()
        installMonitors()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        $state.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateGate() }
        }.store(in: &cancellables)
    }

    func stop() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        gate = nil
    }

    func restart() {
        stop()
        start()
    }

    @objc private func screensChanged() {
        metrics = NotchGeometry.metrics()
        guard let panel else { return }
        let size = NotchGeometry.windowSize
        let screen = metrics.screen
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        updateGate()
    }

    // MARK: Shell geometry

    /// On a display with no physical notch there is no hardware to blend into.
    /// With hover on, a small handle marks where to point. With hover off
    /// nothing should sit in the menu bar at all, so the collapsed shell is an
    /// invisible sliver at the top edge that the shortcut grows downward.
    var hidesWhenCollapsed: Bool {
        !metrics.hasRealNotch && !Settings.shared.notchOpensOnHover
    }

    /// Re-evaluates anything derived from settings (called when they change).
    func settingsChanged() {
        objectWillChange.send()
        updateGate()
    }

    var shellSize: CGSize {
        switch state {
        case .collapsed:
            return hidesWhenCollapsed
                ? CGSize(width: metrics.notchSize.width, height: 1)
                : metrics.notchSize
        case .dropZone: return NotchGeometry.dropZoneSize(notch: metrics.notchSize)
        case .expanded: return NotchGeometry.expandedSize(notch: metrics.notchSize)
        }
    }

    /// Region that should receive mouse events, in the window's top-left coordinates.
    private var activeRect: CGRect {
        let win = NotchGeometry.windowSize
        let s = shellSize
        // Collapsed keeps a slightly wider/taller strip so the pointer reliably
        // finds the notch on the way past.
        if state == .dropZone {
            // Widen the catch area well beyond the visible target so the drop is easy.
            return CGRect(x: 0, y: 0, width: win.width,
                          height: NotchGeometry.dropZoneSize(notch: metrics.notchSize).height + 34)
        }
        if state == .collapsed && !Settings.shared.notchOpensOnHover {
            return .zero   // nothing to hover; let clicks fall through to the desktop
        }
        let padX: CGFloat = state == .collapsed ? 26 : 0
        let padY: CGFloat = state == .collapsed ? 6 : 0
        return CGRect(x: (win.width - s.width) / 2 - padX, y: 0,
                      width: s.width + padX * 2, height: s.height + padY)
    }

    private func updateGate() {
        gate?.activeRect = activeRect
    }

    // MARK: Pointer

    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .scrollWheel]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.pointerMoved(NSEvent.mouseLocation)
        }) { monitors.append(g) }

        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.pointerMoved(NSEvent.mouseLocation)
            return event
        }) { monitors.append(l) }

        // A low-frequency safety net: global monitors go quiet when the pointer
        // stops, and we must still notice it having left the shell.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pointerMoved(NSEvent.mouseLocation)
        }
        RunLoop.main.add(timer, forMode: .common)
        monitors.append(timer)
    }

    private func removeMonitors() {
        for m in monitors {
            if let t = m as? Timer { t.invalidate() } else { NSEvent.removeMonitor(m) }
        }
        monitors = []
    }

    private func pointerMoved(_ screenPoint: CGPoint) {
        guard let panel else { return }
        let f = panel.frame
        let local = CGPoint(x: screenPoint.x - f.minX, y: f.maxY - screenPoint.y)
        let inWindow = local.x >= 0 && local.y >= 0 && local.x <= f.width && local.y <= f.height
        let newPointer = inWindow ? local : nil
        if newPointer != pointer { pointer = newPointer }

        let trigger = triggerRect
        // Hovering only opens the shell when the user has asked for that; once it
        // is open, the pointer still keeps it open.
        // Never let a stray pointer move dismiss an active drop target.
        if state == .dropZone { return }
        let hoverMayOpen = Settings.shared.notchOpensOnHover || state == .expanded
        if let p = newPointer, hoverMayOpen, trigger.contains(p) {
            expand()
        } else if state == .expanded, !holdOpen, !isDropTargeted, !openedByShortcut {
            // Give a generous margin so brushing the edge doesn't slam it shut.
            let expanded = NotchGeometry.expandedSize(notch: metrics.notchSize)
            let keepOpen = CGRect(x: (NotchGeometry.windowSize.width - expanded.width) / 2 - 30,
                                  y: 0,
                                  width: expanded.width + 60,
                                  height: expanded.height + 30)
            if newPointer.map({ !keepOpen.contains($0) }) ?? true {
                scheduleCollapse()
            }
        }
    }

    /// The hover hot-zone: the notch itself plus a few points below it.
    private var triggerRect: CGRect {
        let win = NotchGeometry.windowSize
        let n = metrics.notchSize
        if state == .dropZone {
            // Deliberately forgiving: a dragged file only has to reach the top strip.
            return CGRect(x: 0, y: 0, width: win.width,
                          height: NotchGeometry.dropZoneSize(notch: metrics.notchSize).height + 34)
        }
        if state == .expanded {
            let expanded = NotchGeometry.expandedSize(notch: metrics.notchSize)
            return CGRect(x: (win.width - expanded.width) / 2, y: 0,
                          width: expanded.width, height: expanded.height)
        }
        return CGRect(x: (win.width - n.width) / 2 - 20, y: 0,
                      width: n.width + 40, height: n.height + 8)
    }

    // MARK: State transitions

    func showDropZone() {
        collapseWork?.cancel()
        guard state == .collapsed else { return }
        withAnimation(Theme.snappy) { state = .dropZone }
        updateGate()
    }

    /// The keyboard shortcut: opens if closed, closes if open.
    func toggleFromShortcut() {
        StashLog.write("notch shortcut: state=\(state) panel=\(panel != nil) screen=\(metrics.screen.localizedName) realNotch=\(metrics.hasRealNotch)")
        if state == .expanded {
            collapse()
        } else {
            openedByShortcut = true
            expand()
        }
    }

    func expand() {
        collapseWork?.cancel()
        guard state != .expanded else { return }
        Paster.rememberFrontmostApp()
        withAnimation(Theme.snappy) { state = .expanded }
        updateGate()
    }

    func collapse() {
        collapseWork?.cancel()
        openedByShortcut = false
        guard state != .collapsed else { return }
        withAnimation(Theme.snappy) { state = .collapsed }
        updateGate()
    }

    private func scheduleCollapse(after delay: TimeInterval = 0.22) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.holdOpen, !self.isDropTargeted, !self.openedByShortcut else { return }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Paste from the shell, then get out of the way.
    func activate(_ item: ClipItem) {
        collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Paster.paste(item)
        }
    }
}
