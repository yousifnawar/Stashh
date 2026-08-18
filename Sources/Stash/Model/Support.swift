import Foundation
import AppKit
import CryptoKit

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var sha256: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func truncated(_ n: Int) -> String {
        count <= n ? self : String(prefix(n)) + "…"
    }

    /// First non-empty line, collapsed — used as a card title.
    var firstLine: String {
        for raw in split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmed
            if !line.isEmpty { return line }
        }
        return trimmed
    }
}

extension Data {
    var sha256: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmed
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }

    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        let l = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return l > 0.6
    }
}

enum JSONBox {
    static func encode<T: Encodable>(_ v: T) -> String {
        (try? String(data: JSONEncoder().encode(v), encoding: .utf8) ?? "") ?? ""
    }
    static func decode<T: Decodable>(_ s: String?, _ type: T.Type, default def: T) -> T {
        guard let s, let d = s.data(using: .utf8), let v = try? JSONDecoder().decode(T.self, from: d)
        else { return def }
        return v
    }
}

enum Paths {
    /// Set before anything touches the store to redirect all storage — used by the
    /// preview renderer so it cannot write into the user's real library.
    static var overrideRoot: URL?

    static let root: URL = {
        let base = overrideRoot ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stash", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static let blobs: URL = sub("Blobs")
    static let thumbs: URL = sub("Thumbnails")
    static let texts: URL = sub("Texts")
    static var database: URL { root.appendingPathComponent("stash.sqlite") }

    private static func sub(_ name: String) -> URL {
        let u = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

/// Spotlight-ish fuzzy scoring: subsequence match with bonuses for word starts,
/// consecutive runs and prefix hits. Returns nil when the query does not match.
enum Fuzzy {
    static func score(_ query: String, _ candidate: String) -> Double? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !c.isEmpty, q.count <= c.count else { return nil }

        var score = 0.0
        var ci = 0
        var lastMatch = -2
        for ch in q {
            var found = false
            while ci < c.count {
                let cur = c[ci]
                if cur == ch {
                    var bonus = 1.0
                    if ci == lastMatch + 1 { bonus += 3.0 }                 // consecutive
                    if ci == 0 { bonus += 5.0 }                             // prefix
                    else if !c[ci - 1].isLetter && !c[ci - 1].isNumber { bonus += 2.5 } // word start
                    score += bonus
                    lastMatch = ci
                    ci += 1
                    found = true
                    break
                }
                ci += 1
            }
            if !found { return nil }
        }
        // Prefer shorter candidates so exact-ish hits float up.
        score -= Double(c.count) * 0.01
        if c.count >= q.count, String(c.prefix(q.count)) == String(q) { score += 8 }
        return score
    }
}
