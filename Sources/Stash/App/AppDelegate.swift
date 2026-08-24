import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    private var pruneTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !handOffToRunningInstance() else { return }
        NSApp.setActivationPolicy(.accessory)

        MenuBarController.shared.install()
        HotKeys.installDefaults()
        ClipboardMonitor.shared.start()
        ScreenshotWatcher.shared.start()
        DragWatcher.shared.start()
        NotchController.shared.start()

        NotificationCenter.default.publisher(for: .stashShowQuickSearch)
            .receive(on: DispatchQueue.main)
            .sink { _ in QuickSearchController.shared.show() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .stashShowLibrary)
            .receive(on: DispatchQueue.main)
            .sink { _ in LibraryWindowController.shared.show() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .stashNotchPreferenceChanged)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                Settings.shared.notchEnabled
                    ? NotchController.shared.start()
                    : NotchController.shared.stop()
            }
            .store(in: &cancellables)

        // Retention sweep now and once a day after.
        ClipStore.shared.prune(olderThanDays: Settings.shared.retentionDays)
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { _ in
            ClipStore.shared.prune(olderThanDays: Settings.shared.retentionDays)
        }
        RunLoop.main.add(t, forMode: .common)
        pruneTimer = t

        if !Permissions.hasAccessibility {
            // Give the UI a beat to settle before the system prompt appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Permissions.promptForAccessibilityOnce()
            }
        }

        if isFirstRun || !OnboardingWindowController.hasSeenTutorial {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                OnboardingWindowController.shared.show()
            }
        }
    }

    /// Two copies would each keep their own in-memory history and overwrite the
    /// other's rows, so a second launch just wakes the original.
    private func handOffToRunningInstance() -> Bool {
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.nawar.stash")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let other = others.first else { return false }
        other.activate()
        NSApp.terminate(nil)
        return true
    }

    private var isFirstRun: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        ScreenshotWatcher.shared.stop()
        DragWatcher.shared.stop()
        NotchController.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        LibraryWindowController.shared.show()
        return true
    }
}
