import Foundation
import AppKit
import UniformTypeIdentifiers
import Carbon.HIToolbox

/// `Stash --selftest` exercises the drop and drag plumbing headlessly, since a
/// real drag needs a human hand. Runs against a throwaway store.
@MainActor
enum SelfTest {

    private static var failures = 0

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }

        Paths.overrideRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stash-selftest-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "com.nawar.stash.selftest.\(UUID().uuidString)"
        Shortcuts.defaultsStore = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        _ = ClipStore.shared
        pump(0.4)

        testMultiFileDrop()
        testBrowserImageDrop()
        testMixedDropOrdering()
        testPasteboardWriters()
        testShortcutBinding()
        testShortcutPersistence()
        testShelf()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        // Exit code matters: CI treats a non-zero status as a failed build.
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: Tests

    private static func testMultiFileDrop() {
        let urls = (1...5).map { makePNG(named: "shot-\($0)", hue: CGFloat($0) / 6) }
        let providers = urls.map { NSItemProvider(contentsOf: $0)! }

        var payloads: [DropIngest.Payload] = []
        var done = false
        DropIngest.collect(providers) { payloads = $0; done = true }
        pump(until: { done })

        check("5 dropped files all resolve", payloads.count == 5)
        let names = payloads.compactMap { if case .file(let u) = $0 { return u.lastPathComponent } else { return nil } }
        check("drop order preserved", names == urls.map(\.lastPathComponent), "got \(names)")

        let before = ClipStore.shared.items.count
        Paster.ingestDropped(payloads)
        pump(until: { ClipStore.shared.items.count >= before + 5 })
        check("all 5 became clips", ClipStore.shared.items.count == before + 5,
              "count \(ClipStore.shared.items.count) vs \(before + 5)")
        check("first dropped is newest", ClipStore.shared.items.first?.title == "shot-1.png",
              "newest = \(ClipStore.shared.items.first?.title ?? "nil")")
        check("images got blobs on disk",
              ClipStore.shared.items.prefix(5).allSatisfy {
                  $0.blobPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
              })
        check("images typed as images", ClipStore.shared.items.prefix(5).allSatisfy { $0.kind == .image })
    }

    private static func testBrowserImageDrop() {
        // A drag out of a web page carries bytes, not a file on disk.
        let data = try! Data(contentsOf: makePNG(named: "from-web", hue: 0.5))
        let provider = NSItemProvider()
        provider.suggestedName = "logo.png"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier,
                                            visibility: .all) { done in
            done(data, nil); return nil
        }

        var payloads: [DropIngest.Payload] = []
        var finished = false
        DropIngest.collect([provider]) { payloads = $0; finished = true }
        pump(until: { finished })

        var isImageData = false
        if case .imageData = payloads.first { isImageData = true }
        check("raw image bytes accepted", isImageData, "got \(payloads.count) payloads")

        let before = ClipStore.shared.items.count
        Paster.ingestDropped(payloads)
        pump(until: { ClipStore.shared.items.count > before })
        check("byte-only image stored", ClipStore.shared.items.count == before + 1)
        check("named from the drag", ClipStore.shared.items.first?.title == "logo")
    }

    private static func testMixedDropOrdering() {
        let a = makePNG(named: "mixed-a", hue: 0.1)
        let b = makePNG(named: "mixed-b", hue: 0.7)
        let text = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notes.txt")
        try? "hello".write(to: text, atomically: true, encoding: .utf8)

        let providers = [a, text, b].map { NSItemProvider(contentsOf: $0)! }
        var payloads: [DropIngest.Payload] = []
        var done = false
        DropIngest.collect(providers) { payloads = $0; done = true }
        pump(until: { done })

        check("mixed drag keeps all 3", payloads.count == 3)
        let mixedBefore = ClipStore.shared.items.count
        Paster.ingestDropped(payloads)
        pump(until: { ClipStore.shared.items.count >= mixedBefore + 3 })
        let top3 = ClipStore.shared.items.prefix(3).map(\.title)
        check("mixed order preserved", top3 == ["mixed-a.png", "notes.txt", "mixed-b.png"],
              "got \(top3)")
        check("non-image kept as file", ClipStore.shared.items.first { $0.title == "notes.txt" }?.kind == .file)
    }

    private static func testPasteboardWriters() {
        let images = ClipStore.shared.items.filter { $0.kind == .image }.prefix(3)
        let writers = images.compactMap { Paster.pasteboardWriter(for: $0) }
        check("every image vends a drag writer", writers.count == images.count)
        check("images drag as file URLs", writers.allSatisfy { $0 is NSURL })

        var textClip = ClipItem()
        textClip.kind = .text
        textClip.text = "plain"
        check("text drags as a string", Paster.pasteboardWriter(for: textClip) is NSString)

        let dragImage = Paster.dragImage(for: Array(images)[0])
        check("drag preview has pixels", dragImage.size.width > 0 && dragImage.size.height > 0)
    }

    private static func testShortcutBinding() {
        let shortcuts = Shortcuts.shared
        shortcuts.resetAll()

        check("defaults bound for every action",
              ShortcutID.allCases.allSatisfy { shortcuts.combo($0) != nil })
        check("notch defaults to ⌘P", shortcuts.label(.notch) == "⌘P", shortcuts.label(.notch))
        check("search defaults to ⇧⌘V", shortcuts.label(.quickSearch) == "⇧⌘V",
              shortcuts.label(.quickSearch))

        // Rebinding
        let f5 = KeyCombo(keyCode: UInt16(kVK_F5), modifiers: [])
        shortcuts.set(f5, for: .notch)
        check("rebound to a bare function key", shortcuts.label(.notch) == "F5", shortcuts.label(.notch))
        check("function keys need no modifier", f5.isUsable)

        let bare = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [])
        check("bare letter rejected", !bare.isUsable)
        let shiftOnly = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.shift])
        check("shift alone rejected", !shiftOnly.isUsable)

        let optCtrl = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.option, .control])
        check("⌃⌥ accepted", optCtrl.isUsable)
        check("modifier order matches macOS", optCtrl.displayString == "⌃⌥K", optCtrl.displayString)

        // Carbon translation
        let all = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift, .option, .control])
        let expected = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        check("carbon modifier mask correct", all.carbonModifiers == expected)

        // Conflicts
        let searchCombo = shortcuts.combo(.quickSearch)!
        check("clash with another action detected",
              shortcuts.conflict(with: searchCombo, excluding: .notch) == .quickSearch)
        check("no clash against itself",
              shortcuts.conflict(with: searchCombo, excluding: .quickSearch) == nil)

        // System shadowing advice
        let cmdP = KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command])
        check("⌘P warns about Print", shortcuts.systemWarning(for: cmdP)?.contains("Print") == true)
        let cmdShiftP = KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command, .shift])
        check("⇧⌘P does not warn", shortcuts.systemWarning(for: cmdShiftP) == nil)
    }

    private static func testShortcutPersistence() {
        let shortcuts = Shortcuts.shared
        shortcuts.resetAll()

        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .option])
        shortcuts.set(combo, for: .library)
        check("custom binding survives a round trip",
              storedBindings()["library"] == combo)

        shortcuts.set(nil, for: .quickSearch)
        check("cleared shortcut has no binding", shortcuts.combo(.quickSearch) == nil)
        check("cleared shortcut recorded as cleared",
              storedCleared().contains("quickSearch"), "\(storedCleared())")
        check("label reads as unset", shortcuts.labelOrNone(.quickSearch) == "not set")

        shortcuts.resetAll()
        check("reset restores every default",
              ShortcutID.allCases.allSatisfy { shortcuts.combo($0) == $0.defaultCombo })
        check("reset clears the cleared list", storedCleared().isEmpty, "\(storedCleared())")
    }

    private static func testShelf() {
        let shelf = ShelfStore.shared
        shelf.clear()
        pump(until: { shelf.isEmpty })

        // Park three files, one of them an image.
        let doc = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("report.pdf")
        try? Data("not really a pdf".utf8).write(to: doc)
        let img = makePNG(named: "shelf-shot", hue: 0.3)
        let txt = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("todo.txt")
        try? "buy milk".write(to: txt, atomically: true, encoding: .utf8)

        let added = shelf.add(urls: [doc, img, txt])
        check("three files parked", added == 3, "added \(added)")
        // Staging runs on a background queue — wait for it instead of sleeping a
        // fixed amount, which is flaky on a slower machine.
        pump(until: { shelf.items.count == 3 && shelf.items.allSatisfy { $0.blobPath != nil } })

        let titles = shelf.items.map(\.title)
        check("drop order preserved", titles == ["report.pdf", "shelf-shot.png", "todo.txt"],
              "got \(titles)")
        check("image recognised as an image",
              shelf.items.first { $0.title == "shelf-shot.png" }?.kind == .image)
        check("document kept as a file",
              shelf.items.first { $0.title == "report.pdf" }?.kind == .file)
        // Thumbnailing falls back to the system icon service, which is not
        // guaranteed to produce anything on a headless machine. A missing
        // thumbnail degrades to the type glyph, so it is not a failure.
        let thumbed = shelf.items.filter { $0.thumbPath != nil }.count
        print("  · \(thumbed)/3 got thumbnails (cosmetic, environment-dependent)")

        // Staging: the shelf must survive the original being deleted.
        check("files staged into Stash's own storage",
              shelf.items.allSatisfy { $0.blobPath != nil }, "\(shelf.items.map(\.blobPath))")
        try? FileManager.default.removeItem(at: doc)
        let parked = shelf.items.first { $0.title == "report.pdf" }!
        check("survives the original being deleted", !ShelfStore.isMissing(parked))
        check("drag uses the staged copy",
              (Paster.pasteboardWriter(for: parked) as? NSURL)?.path == parked.blobPath,
              "\(String(describing: (Paster.pasteboardWriter(for: parked) as? NSURL)?.path))")

        // Duplicates
        let again = shelf.add(urls: [img])
        check("same file is not parked twice", again == 0 && shelf.items.count == 3,
              "added \(again), count \(shelf.items.count)")

        // The shelf is not the clip history
        let historyBefore = ClipStore.shared.items.count
        check("shelf entries stay out of the history",
              !ClipStore.shared.items.contains { $0.title == "report.pdf" })
        shelf.keepInHistory(parked)
        pump(until: { ClipStore.shared.items.count > historyBefore })
        check("keeping one promotes it to the history",
              ClipStore.shared.items.count == historyBefore + 1,
              "\(ClipStore.shared.items.count) vs \(historyBefore + 1)")

        // Removal
        shelf.remove(parked)
        pump(until: { shelf.items.count == 2 })
        check("removing takes it off the shelf", shelf.items.count == 2)
        shelf.clear()
        pump(until: { shelf.isEmpty })
        check("emptying clears everything", shelf.isEmpty)
    }

    private static func storedRaw() -> [String: Any] {
        guard let data = Shortcuts.defaultsStore.data(forKey: "shortcutBindings"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func storedBindings() -> [String: KeyCombo] {
        guard let data = Shortcuts.defaultsStore.data(forKey: "shortcutBindings"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["bindings"],
              let inner = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode([String: KeyCombo].self, from: inner)
        else { return [:] }
        return decoded
    }

    private static func storedCleared() -> [String] {
        (storedRaw()["cleared"] as? [String]) ?? []
    }

    // MARK: Helpers

    private static func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        if passed {
            print("  ✓ \(name)")
        } else {
            failures += 1
            print("  ✗ \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    private static func makePNG(named: String, hue: CGFloat) -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        NSGraphicsContext.restoreGraphicsState()

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(named).png")
        try? rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func pump(until condition: () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
