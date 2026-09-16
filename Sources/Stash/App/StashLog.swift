import Foundation

/// A small append-only log at ~/Library/Logs/Stash/stash.log.
///
/// The unified log is unreliable to search after the fact, and "the shortcut
/// does nothing" is exactly the kind of report that needs a record of what the
/// app actually saw. Kept short: one line per event, trimmed when it grows.
enum StashLog {
    private static let queue = DispatchQueue(label: "com.nawar.stash.log")

    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Stash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stash.log")
    }()

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
            trimIfLarge()
        }
    }

    private static func trimIfLarge() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > 512_000,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let kept = text.split(separator: "\n").suffix(1000).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }
}
