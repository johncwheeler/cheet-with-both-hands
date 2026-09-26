import Foundation

public enum HotkeyAction: Hashable, Sendable {
    case showCheet(UUID)
    case showPicker
    case toggleLastCheet
    case toggleGhostMode
    case showCheetAlongside(UUID)
}

public struct HotkeyBinding: Hashable, Sendable {
    public var combo: KeyCombo
    public var action: HotkeyAction
    public var isAutomatic: Bool
}

public struct HotkeyPlan: Sendable, Equatable {
    /// Bindings to register (conflict-free).
    public var bindings: [HotkeyBinding] = []
    /// Effective combo for each cheet that won its combo.
    public var cheetCombos: [UUID: KeyCombo] = [:]
    /// Actions whose requested combo was already taken, with the combo they asked for.
    public var conflicts: [HotkeyAction: KeyCombo] = [:]

    public init() {}

    public func combo(for action: HotkeyAction) -> KeyCombo? {
        bindings.first { $0.action == action }?.combo
    }
}

/// Resolves which combo triggers what. Priority on collisions:
/// global actions → custom cheet combos → automatic number combos; earlier cheets win ties.
public enum HotkeyResolver {
    public static let automaticSlots = KeyCodes.digitRow.count

    public static func automaticCombo(forIndex index: Int, base: ModifierSet) -> KeyCombo? {
        guard base.hasPrimaryModifier, index >= 0, index < automaticSlots else { return nil }
        return KeyCombo(keyCode: KeyCodes.digitRow[index], modifiers: base)
    }

    /// The number shown for a cheet position (1…9, then 0 for the tenth).
    public static func slotLabel(forIndex index: Int) -> String? {
        guard index >= 0, index < automaticSlots else { return nil }
        return index == 9 ? "0" : "\(index + 1)"
    }

    public static func resolve(cheets: [Cheet], settings: HotkeySettings) -> HotkeyPlan {
        var plan = HotkeyPlan()
        var taken: Set<KeyCombo> = []

        func claim(_ combo: KeyCombo?, for action: HotkeyAction, automatic: Bool = false) {
            guard let combo else { return }
            if taken.contains(combo) {
                plan.conflicts[action] = combo
                return
            }
            taken.insert(combo)
            plan.bindings.append(HotkeyBinding(combo: combo, action: action, isAutomatic: automatic))
            if case .showCheet(let id) = action { plan.cheetCombos[id] = combo }
        }

        claim(settings.picker, for: .showPicker)
        claim(settings.toggleLast, for: .toggleLastCheet)
        claim(settings.ghostMode, for: .toggleGhostMode)

        for cheet in cheets where cheet.hotkey.mode == .custom {
            claim(cheet.hotkey.combo, for: .showCheet(cheet.id))
        }
        if settings.autoNumbering {
            for (index, cheet) in cheets.enumerated() where cheet.hotkey.mode == .automatic {
                claim(automaticCombo(forIndex: index, base: settings.baseModifiers), for: .showCheet(cheet.id), automatic: true)
            }
        }
        // Lowest priority: ⇧ variants of every cheet combo that won, for "open alongside".
        if settings.shiftForAlongside {
            for cheet in cheets {
                guard let combo = plan.cheetCombos[cheet.id], !combo.modifiers.contains(.shift) else { continue }
                claim(KeyCombo(keyCode: combo.keyCode, modifiers: combo.modifiers.union(.shift)), for: .showCheetAlongside(cheet.id))
            }
        }
        return plan
    }
}
