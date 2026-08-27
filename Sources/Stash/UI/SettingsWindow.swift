import SwiftUI
import AppKit

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 540),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Stash Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 1)
            w.contentView = NSHostingView(rootView: SettingsView())
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var store = ClipStore.shared
    @State private var accessibilityGranted = Permissions.hasAccessibility
    @State private var folderTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.top, 26)

                if Permissions.needsAccessibility, !accessibilityGranted {
                    permissionCard
                }

                group("Capture") {
                    Toggle("Save everything I copy", isOn: $settings.captureEnabled)
                    Toggle("Save new screenshots automatically", isOn: $settings.captureScreenshots)
                        .onChange(of: settings.captureScreenshots) { _, _ in
                            ScreenshotWatcher.shared.restart()
                        }
                    if settings.captureScreenshots { screenshotFolderRow }
                    Toggle("Play a sound on capture", isOn: $settings.playSound)
                }

                group("Notch Shell") {
                    Toggle("Show the notch shell", isOn: $settings.notchEnabled)
                    Toggle("Open it when I hover the notch", isOn: $settings.notchOpensOnHover)
                        .disabled(!settings.notchEnabled)
                    Text(settings.notchOpensOnHover
                         ? "Move your pointer onto the notch and your clips slide out; move away and it closes again."
                         : "The shell stays out of your way — it only opens from its shortcut or the menu bar.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }

                group("File Shelf") {
                    Toggle("Catch files dragged to the top of the screen", isOn: $settings.shelfEnabled)
                    Text(settings.shelfEnabled
                         ? "Drag any file toward the notch and a drop target appears. Parked files wait on the Shelf tab until you drag them somewhere else."
                         : "Dragging files to the notch does nothing. The Shelf tab still holds anything already parked there.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }

                group("Shortcuts") {
                    ShortcutsSection()
                }

                group("Pasting") {
                    if Permissions.needsAccessibility {
                        Toggle("Paste directly into the app I was using", isOn: $settings.pasteDirectly)
                        Text("Needs Accessibility permission. When off, Stash only puts the clip on your clipboard.")
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    } else {
                        Text("Choosing a clip copies it and brings back the app you were using — press ⌘V to drop it in.")
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }
                }

                group("History") {
                    HStack {
                        Text("Keep unpinned clips for")
                        Spacer()
                        Picker("", selection: $settings.retentionDays) {
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                            Text("Forever").tag(0)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    HStack {
                        Text("\(store.items.count) clips stored")
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        Spacer()
                        Button("Clear Unpinned") { store.deleteAll(keepPinned: true) }
                        Button("Reveal Data") {
                            NSWorkspace.shared.activateFileViewerSelecting([Paths.root])
                        }
                    }
                }

                group("Privacy") {
                    Text("Stash never records clips copied from these apps:")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    ForEach(settings.ignoredApps, id: \.self) { bundle in
                        HStack(spacing: 6) {
                            AppBadge(bundleID: bundle, size: 14)
                            Text(appName(for: bundle))
                                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                            Spacer()
                            Button {
                                settings.ignoredApps.removeAll { $0 == bundle }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.tertiary)
                            }.buttonStyle(.plain)
                        }
                    }
                    Button("Add App…") { pickApp() }
                    Text("Clips marked concealed by password managers are always skipped.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                }

                group("General") {
                    Toggle("Launch Stash at login", isOn: $settings.launchAtLogin)
                    Button("Show the tutorial again") { OnboardingWindowController.shared.show() }
                }

                HStack {
                    Spacer()
                    Button("Quit Stash") { NSApp.terminate(nil) }
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 26)
            .toggleStyle(.switch)
            .tint(Theme.accent)
        }
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .onAppear { accessibilityGranted = Permissions.hasAccessibility }
    }

    /// Sandboxed builds cannot find the screenshot folder on their own.
    @ViewBuilder
    private var screenshotFolderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: ScreenshotFolder.isConfigured ? "folder.fill" : "folder.badge.questionmark")
                .font(.system(size: 11))
                .foregroundStyle(ScreenshotFolder.isConfigured ? Theme.secondary : .orange)
            Text(ScreenshotFolder.displayPath)
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(ScreenshotFolder.isConfigured ? "Change…" : "Choose Folder…") {
                _ = ScreenshotFolder.chooseFolder()
                folderTick &+= 1
            }
            .font(.system(size: 11))
        }
        .id(folderTick)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission needed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Grant it so Stash can paste straight into the app you were using. Without it, clips are only copied to your clipboard.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            HStack {
                Button("Open Settings") { Permissions.openAccessibilitySettings() }
                Button("Re-check") { accessibilityGranted = Permissions.hasAccessibility }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold)).tracking(0.6)
                .foregroundStyle(Theme.tertiary)
            content()
                .font(.system(size: 12))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func appName(for bundle: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return url.deletingPathExtension().lastPathComponent
        }
        // Not installed — show the readable tail rather than the whole identifier.
        return bundle.split(separator: ".").last.map(String.init)?.capitalized ?? bundle
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url)?.bundleIdentifier {
            if !settings.ignoredApps.contains(bundle) { settings.ignoredApps.append(bundle) }
        }
    }
}
