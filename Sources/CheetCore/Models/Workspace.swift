import CoreGraphics
import Foundation

/// One window in a saved workspace.
public struct WorkspaceWindow: Codable, Hashable, Sendable {
    public var cheetID: UUID
    /// Relative to the display's visible frame.
    public var frame: NormalizedRect
    /// The display's UUID (CGDisplayCreateUUIDFromDisplayID), stable across reboots; nil if unknown.
    public var displayID: String?

    public init(cheetID: UUID, frame: NormalizedRect, displayID: String?) {
        self.cheetID = cheetID
        self.frame = frame
        self.displayID = displayID
    }
}

/// A display, as far as restoring workspace frames is concerned.
public struct ScreenInfo: Equatable, Sendable {
    public var displayID: String?
    public var visibleFrame: CGRect

    public init(displayID: String?, visibleFrame: CGRect) {
        self.displayID = displayID
        self.visibleFrame = visibleFrame
    }
}

extension WorkspaceWindow {
    /// Where to put this window: on its own display if it's connected, otherwise on `fallback`,
    /// kept inside that screen's visible frame.
    public func restoredFrame(on screens: [ScreenInfo], fallback: ScreenInfo, minSize: CGSize) -> CGRect {
        let screen = screens.first { $0.displayID != nil && $0.displayID == displayID } ?? fallback
        return frame.denormalized(in: screen.visibleFrame).clamped(to: screen.visibleFrame, minSize: minSize)
    }
}

/// A named set of cheet windows and their frames. Windows are ordered back to front; the last one
/// is focused (the active window) when the workspace is recalled.
public struct Workspace: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var windows: [WorkspaceWindow]
    public var hotkey: KeyCombo?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, windows: [WorkspaceWindow], hotkey: KeyCombo? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.windows = windows
        self.hotkey = hotkey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The workspace without windows for cheets that no longer exist.
    public func pruned(keeping cheetIDs: Set<UUID>) -> Workspace {
        var copy = self
        copy.windows = windows.filter { cheetIDs.contains($0.cheetID) }
        return copy
    }

    /// "Git + Vim", "Git + Vim + tmux + 2 more", or "Workspace" when nothing is open.
    public static func suggestedName(for titles: [String]) -> String {
        guard !titles.isEmpty else { return "Workspace" }
        let shown = titles.prefix(3).joined(separator: " + ")
        return titles.count > 3 ? "\(shown) + \(titles.count - 3) more" : shown
    }
}

extension Workspace: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, windows, hotkey, createdAt, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Workspace")
        windows = c.value(.windows, or: [])
        hotkey = c.optionalValue(.hotkey)
        createdAt = c.value(.createdAt, or: Date())
        updatedAt = c.value(.updatedAt, or: createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(windows, forKey: .windows)
        try c.encodeIfPresent(hotkey, forKey: .hotkey)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
