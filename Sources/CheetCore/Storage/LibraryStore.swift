import Foundation

/// Everything in library.json: the cheets (in order) and the saved workspaces.
public struct Library: Equatable, Sendable {
    public var cheets: [Cheet]
    public var workspaces: [Workspace]

    public init(cheets: [Cheet], workspaces: [Workspace] = []) {
        self.cheets = cheets
        self.workspaces = workspaces
    }
}

/// Reads and writes the cheet library, settings and view state as JSON in Application Support.
public final class LibraryStore: @unchecked Sendable {
    public let directory: URL

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    public static var defaultDirectory: URL {
        applicationSupport.appendingPathComponent("Cheet with Both Hands", isDirectory: true)
    }

    /// Where the library lived before the app was renamed.
    public static var legacyDirectory: URL {
        applicationSupport.appendingPathComponent("Cheat with Both Hands", isDirectory: true)
    }

    /// Moves data from the pre-rename folder into the current one (once, if the new one doesn't exist yet).
    @discardableResult
    public static func migrateLegacyDirectory(from legacy: URL = legacyDirectory, to current: URL = defaultDirectory) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: current.path) else { return false }
        do {
            try fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacy, to: current)
            return true
        } catch {
            return false
        }
    }

    public init(directory: URL = LibraryStore.defaultDirectory) {
        self.directory = directory
    }

    public var libraryURL: URL { directory.appendingPathComponent("library.json") }
    public var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    public var viewStateURL: URL { directory.appendingPathComponent("state.json") }
    public var backupURL: URL { directory.appendingPathComponent("library.backup.json") }

    struct LibraryFile: Codable {
        var version = 2
        var cheets: [Cheet]
        var workspaces: [Workspace]

        init(_ library: Library) {
            cheets = library.cheets
            workspaces = library.workspaces
        }

        private enum CodingKeys: String, CodingKey { case version, cheets, workspaces }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = c.value(.version, or: 1)
            cheets = try c.decode([Cheet].self, forKey: .cheets) // required: this is what makes it a library file
            workspaces = c.value(.workspaces, or: []) // unreadable workspaces must not cost the cheets
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `nil` when no library exists yet (first launch).
    public func loadLibrary() throws -> Library? {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
        return try Self.decodeLibrary(from: Data(contentsOf: libraryURL))
    }

    /// The cheets alone (read-only convenience; saving always writes the whole library).
    public func loadCheets() throws -> [Cheet]? {
        try loadLibrary()?.cheets
    }

    public func saveLibrary(_ library: Library) throws {
        try ensureDirectory()
        try Self.encodeLibrary(library).write(to: libraryURL, options: .atomic)
    }

    /// Keeps a copy of the library as it was at launch, in case something goes wrong.
    public func backupLibrary() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: libraryURL, to: backupURL)
    }

    public func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return AppSettings() }
        let migrated = LegacyKeys.rename(in: data, [["layout", "perSheetFrames"]: "perCheetFrames"])
        return ResilientJSON.decode(AppSettings.self, from: migrated, defaults: AppSettings())
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try ensureDirectory()
        try JSONEncoder.cheet.encode(settings).write(to: settingsURL, options: .atomic)
    }

    public func loadViewState() -> ViewState {
        guard let data = try? Data(contentsOf: viewStateURL) else { return ViewState() }
        let migrated = LegacyKeys.rename(in: data, [["lastSheetID"]: "lastCheetID", ["sheets"]: "cheets"])
        return ResilientJSON.decode(ViewState.self, from: migrated, defaults: ViewState())
    }

    public func saveViewState(_ state: ViewState) throws {
        try ensureDirectory()
        try JSONEncoder.cheet.encode(state).write(to: viewStateURL, options: .atomic)
    }

    // MARK: - Library export / import

    public static func encodeLibrary(_ library: Library) throws -> Data {
        try JSONEncoder.cheet.encode(LibraryFile(library))
    }

    /// Accepts a library file (with or without workspaces), a bare array of cheets, or a single cheet.
    public static func decodeLibrary(from data: Data) throws -> Library {
        let data = LegacyKeys.rename(in: data, [["sheets"]: "cheets"])
        let decoder = JSONDecoder.cheet
        if let file = try? decoder.decode(LibraryFile.self, from: data) {
            return Library(cheets: file.cheets, workspaces: file.workspaces)
        }
        if let cheets = try? decoder.decode([Cheet].self, from: data) { return Library(cheets: cheets) }
        return Library(cheets: [try decoder.decode(Cheet.self, from: data)])
    }

    public static func encodeCheet(_ cheet: Cheet) throws -> Data {
        try JSONEncoder.cheet.encode(cheet)
    }
}

/// Renames JSON keys written by versions before the "Cheets" rename, so old files still load.
enum LegacyKeys {
    /// `renames` maps a key path (e.g. `["layout", "perSheetFrames"]`) to the new name of its last key.
    static func rename(in data: Data, _ renames: [[String]: String]) -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        var changed = false
        for (path, newName) in renames {
            if rename(&root, path: path[...], to: newName) { changed = true }
        }
        guard changed, let result = try? JSONSerialization.data(withJSONObject: root) else { return data }
        return result
    }

    private static func rename(_ object: inout [String: Any], path: ArraySlice<String>, to newName: String) -> Bool {
        guard let key = path.first else { return false }
        if path.count == 1 {
            guard let value = object[key], object[newName] == nil else { return false }
            object[newName] = value
            object[key] = nil
            return true
        }
        guard var child = object[key] as? [String: Any] else { return false }
        let changed = rename(&child, path: path.dropFirst(), to: newName)
        if changed { object[key] = child }
        return changed
    }
}
