import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if MainActor.assumeIsolated({ SelfTest.runIfRequested() || PreviewRenderer.runIfRequested() }) {
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
