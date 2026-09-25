import AppKit
import Carbon.HIToolbox
import CheetCore

/// Registers system-wide hotkeys through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission and reports both press and release (used for hold-to-peek).
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    nonisolated fileprivate static let signature: OSType = 0x4357_4248 // 'CWBH'

    var onPress: ((HotkeyAction) -> Void)?
    var onRelease: ((HotkeyAction) -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: HotkeyAction] = [:]
    private var nextID: UInt32 = 1
    private var desiredBindings: [HotkeyBinding] = []
    private var suspendCount = 0

    var isSuspended: Bool { suspendCount > 0 }

    func install() {
        guard handlerRef == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, specs.count, &specs, nil, &handlerRef)
        if status != noErr { NSLog("Cheet with Both Hands: InstallEventHandler failed (\(status))") }
    }

    /// Replaces all registrations. Returns the combos that could not be registered,
    /// or `nil` while suspended (e.g. during shortcut recording).
    @discardableResult
    func register(_ bindings: [HotkeyBinding]) -> Set<KeyCombo>? {
        desiredBindings = bindings
        unregisterAll()
        guard suspendCount == 0 else { return nil }

        var failures = Set<KeyCombo>()
        for binding in bindings {
            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.combo.keyCode,
                binding.combo.modifiers.rawValue,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs[id] = ref
                actions[id] = binding.action
            } else {
                failures.insert(binding.combo)
            }
        }
        return failures
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    /// Temporarily releases every hotkey (so a recorder can capture combos that are already bound).
    func suspend() {
        suspendCount += 1
        if suspendCount == 1 { unregisterAll() }
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        if suspendCount == 0 { register(desiredBindings) }
    }

    fileprivate func handle(id: UInt32, pressed: Bool) {
        guard let action = actions[id] else { return }
        if pressed { onPress?(action) } else { onRelease?(action) }
    }
}

private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        HotkeyCenter.shared.handle(id: id, pressed: pressed)
    }
    return noErr
}
