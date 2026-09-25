import AppKit
import CheetCore
import SwiftUI

/// Click, then press a shortcut. Esc cancels, Delete clears. Global hotkeys are suspended while
/// recording so existing bindings can be captured instead of fired.
struct HotkeyRecorder: View {
    @Binding var combo: KeyCombo?
    var placeholder = "Record Shortcut"
    var allowsClearing = true

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    if isRecording {
                        Image(systemName: "record.circle").foregroundStyle(.red)
                        Text("Type shortcut…").foregroundStyle(.secondary)
                    } else if let combo {
                        Text(combo.displayString).font(.system(.body, design: .rounded).weight(.medium))
                    } else {
                        Text(placeholder).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 118)
            }
            .help(isRecording ? "Press a key combination (Esc to cancel, Delete to clear)" : "Click to record a shortcut")

            if allowsClearing, combo != nil, !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        guard !isRecording else { return }
        isRecording = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyCenter.shared.resume()
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = ModifierSet(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        if modifiers.isEmpty && keyCode == KeyCodes.escape {
            stop()
            return
        }
        if modifiers.isEmpty && (keyCode == KeyCodes.delete || keyCode == KeyCodes.forwardDelete) {
            if allowsClearing { combo = nil }
            stop()
            return
        }
        guard modifiers.hasPrimaryModifier || KeyCodes.isFunctionKey(keyCode) else {
            NSSound.beep() // needs ⌃, ⌥ or ⌘ (function keys may stand alone)
            return
        }
        combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        stop()
    }
}

/// Toggle chips for choosing a modifier-only base combo (⌃ ⌥ ⇧ ⌘).
struct ModifierPicker: View {
    @Binding var selection: ModifierSet

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ModifierSet.displayOrder, id: \.1) { modifier, symbol, name in
                let isOn = selection.contains(modifier)
                Button {
                    if isOn { selection.remove(modifier) } else { selection.insert(modifier) }
                } label: {
                    Text(symbol)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(width: 34, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
    }
}
