import Foundation
import AppKit

/// Where new screenshots are found.
///
/// Outside the sandbox this is read straight from macOS's own preference. Inside
/// it, neither that preference nor the folder itself is reachable, so the user
/// picks the folder once and a security-scoped bookmark reopens it afterwards.
enum ScreenshotFolder {

    private static let bookmarkKey = "screenshotFolderBookmark"
    private static var accessing: URL?

    /// True when Stash can actually watch a folder right now.
    static var isConfigured: Bool { resolve() != nil }

    static func resolve() -> URL? {
        #if APPSTORE
        return resolveBookmark()
        #else
        return systemLocation()
        #endif
    }

    /// A label for Settings.
    static var displayPath: String {
        resolve()?.path ?? "Not chosen"
    }

    // MARK: Unsandboxed

    /// Reads `com.apple.screencapture location`, falling back to the Desktop.
    private static func systemLocation() -> URL? {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let loc = defaults?.string(forKey: "location") {
            let expanded = (loc as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    // MARK: Sandboxed

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale { save(url) }   // refresh before it expires entirely

        if accessing != url {
            accessing.map { $0.stopAccessingSecurityScopedResource() }
            guard url.startAccessingSecurityScopedResource() else { return nil }
            accessing = url
        }
        return url
    }

    private static func save(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Asks the user which folder their screenshots land in.
    @discardableResult
    static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch This Folder"
        panel.message = "Choose the folder your screenshots are saved to — usually the Desktop."
        panel.directoryURL = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        save(url)
        accessing.map { $0.stopAccessingSecurityScopedResource() }
        accessing = nil
        ScreenshotWatcher.shared.restart()
        return true
    }

    static func forget() {
        accessing.map { $0.stopAccessingSecurityScopedResource() }
        accessing = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        ScreenshotWatcher.shared.restart()
    }
}
