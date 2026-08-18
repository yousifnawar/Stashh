import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click it, press a combination, done. While recording, every Stash hot key is
/// suspended so pressing the shortcut you are rebinding doesn't fire it.
struct ShortcutRecorder: View {
    let id: ShortcutID

    @ObservedObject private var shortcuts = Shortcuts.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var problem: String?

    private var combo: KeyCombo? { shortcuts.combo(id) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    Text(fieldText)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(recording ? Theme.accent : Theme.primary)
                        .frame(minWidth: 78)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(recording ? Theme.accentSoft : Color.white.opacity(0.09))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(recording ? Theme.accent : Color.clear, lineWidth: 1.4)
                        )
                }
                .buttonStyle(.plain)
                .help(recording ? "Press a key combination, or Esc to cancel"
                                : "Click to change this shortcut")

                if combo != nil && !recording {
                    Button {
                        shortcuts.set(nil, for: id)
                        problem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this shortcut")
                }

                if combo != id.defaultCombo && !recording {
                    Button {
                        shortcuts.reset(id)
                        problem = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Back to \(id.defaultCombo.displayString)")
                }
            }

            if let note = problem ?? warning {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(problem != nil ? .red : .orange)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 210, alignment: .trailing)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var fieldText: String {
        if recording {
            let mods = KeyCombo.modifierString(liveModifiers)
            return mods.isEmpty ? "Listening…" : mods + "…"
        }
        return combo?.displayString ?? "Not set"
    }

    private var warning: String? {
        guard let combo, !recording else { return nil }
        return shortcuts.systemWarning(for: combo)
    }

    // MARK: Recording

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        problem = nil
        liveModifiers = []
        recording = true
        shortcuts.suspend()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                liveModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                return nil
            }

            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
                return nil
            case kVK_Delete, kVK_ForwardDelete:
                shortcuts.set(nil, for: id)
                stopRecording()
                return nil
            default:
                break
            }

            let candidate = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags)
            guard candidate.isUsable else {
                problem = "Add ⌘, ⌃ or ⌥ — a plain key would type instead."
                return nil
            }
            if let clash = shortcuts.conflict(with: candidate, excluding: id) {
                problem = "\(candidate.displayString) is already \(clash.title)."
                return nil
            }
            shortcuts.set(candidate, for: id)
            problem = nil
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            shortcuts.resume()
        }
    }
}

/// The Settings block listing every rebindable action.
struct ShortcutsSection: View {
    @ObservedObject private var shortcuts = Shortcuts.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ShortcutID.allCases) { id in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: id.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(id.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.primary)
                        Text(id.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    ShortcutRecorder(id: id)
                }
            }

            HStack {
                Text("Click a shortcut, then press the keys you want. Esc cancels, Delete removes it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset All") { shortcuts.resetAll() }
                    .font(.system(size: 11))
            }
        }
    }
}
