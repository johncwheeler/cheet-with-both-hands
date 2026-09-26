import Foundation
import Testing
@testable import CheetCore

struct KeyCapParserTests {
    @Test func recognisesCommonNotations() {
        #expect(KeyCapParser.parse("Ctrl+Shift+P") == [.chord(["Ctrl", "Shift", "P"])])
        #expect(KeyCapParser.parse("⌘⇧P") == [.chord(["⌘", "⇧", "P"])])
        #expect(KeyCapParser.parse("⌘K ⌘S") == [.chord(["⌘", "K"]), .chord(["⌘", "S"])])
        #expect(KeyCapParser.parse("`Ctrl`+`C`") == [.chord(["Ctrl", "C"])])
        #expect(KeyCapParser.parse("C-x C-s") == [.chord(["Ctrl", "x"]), .chord(["Ctrl", "s"])])
        #expect(KeyCapParser.parse("⇧⌘4 then Space") == [.chord(["⇧", "⌘", "4"]), .separator("then"), .chord(["Space"])])
        #expect(KeyCapParser.parse("⌥← / ⌥→") == [.chord(["⌥", "←"]), .separator("/"), .chord(["⌥", "→"])])
        #expect(KeyCapParser.parse("Ctrl++") == [.chord(["Ctrl", "+"])])
        #expect(KeyCapParser.parse("Cmd-Shift-P") == [.chord(["Cmd", "Shift", "P"])])
        #expect(KeyCapParser.parse("F5") == [.chord(["F5"])])
        #expect(KeyCapParser.parse("`Ctrl` + `Alt` + `Del`") == [.chord(["Ctrl", "Alt", "Del"])])
        #expect(KeyCapParser.parse("Ctrl + C") == [.chord(["Ctrl", "C"])])
        #expect(KeyCapParser.parse("⌃⌥⌘/") == [.chord(["⌃", "⌥", "⌘", "/"])])
        #expect(KeyCapParser.parse("⌘`") == [.chord(["⌘", "`"])])
        #expect(KeyCapParser.parse("⌘,") == [.chord(["⌘", ","])])
        #expect(KeyCapParser.parse("⌘+ / ⌘- / ⌘0") == [.chord(["⌘", "+"]), .separator("/"), .chord(["⌘", "-"]), .separator("/"), .chord(["⌘", "0"])])
        #expect(KeyCapParser.parse("⌘+K") == [.chord(["⌘", "K"])])
        #expect(KeyCapParser.parse("⌘1 … ⌘4") == [.chord(["⌘", "1"]), .separator("…"), .chord(["⌘", "4"])])
        #expect(KeyCapParser.parse("⌘9, ⌘0") == [.chord(["⌘", "9"]), .separator(","), .chord(["⌘", "0"])])
        #expect(KeyCapParser.parse("Ctrl+W s") == [.chord(["Ctrl", "W"]), .chord(["s"])])
    }

    @Test func rejectsProse() {
        #expect(KeyCapParser.parse("Show the command palette") == nil)
        #expect(KeyCapParser.parse("`dd`") == nil)
        #expect(KeyCapParser.parse("`git status`") == nil)
        #expect(KeyCapParser.parse("a b c") == nil)
        #expect(KeyCapParser.parse("Add ⌃") == nil)
        #expect(KeyCapParser.parse("Scroll") == nil)
        #expect(KeyCapParser.parse("^") == nil, "a lone caret is not Control")
        #expect(KeyCapParser.parse("^C") == [.chord(["Ctrl", "C"])])
        #expect(KeyCapParser.parse("Drag") == nil)
        #expect(KeyCapParser.parse("Cmd+Click") == [.chord(["Cmd", "Click"])])
        #expect(KeyCapParser.parse("⌘§•") == nil)
        #expect(KeyCapParser.parse("") == nil)
    }

    @Test func displayStyles() {
        #expect(KeyCapParser.display(["Ctrl", "Shift", "p"], style: .symbols) == ["⌃", "⇧", "P"])
        #expect(KeyCapParser.display(["⌘", "⌥", "Esc"], style: .names) == ["Cmd", "Opt", "Esc"])
        #expect(KeyCapParser.display(["s"], style: .symbols) == ["s"])
        #expect(KeyCapParser.compactSymbolLabel(["⌘", "⇧", "⌃", "P"]) == "⌃⇧⌘P")
        #expect(KeyCapParser.compactSymbolLabel(["⌘", "Space"]) == "⌘ Space")
    }
}

struct HotkeyResolverTests {
    private func cheets(_ n: Int) -> [Cheet] {
        (0..<n).map { Cheet(title: "S\($0)", sections: []) }
    }

    @Test func automaticNumberingCoversTenSlots() {
        let list = cheets(12)
        let plan = HotkeyResolver.resolve(cheets: list, settings: HotkeySettings())
        #expect(plan.cheetCombos.count == 10)
        #expect(plan.cheetCombos[list[0].id]?.keyCode == KeyCodes.one)
        #expect(plan.cheetCombos[list[9].id]?.keyCode == KeyCodes.zero)
        #expect(plan.cheetCombos[list[10].id] == nil)
        #expect(plan.cheetCombos[list[0].id]?.modifiers == [.control, .option, .command])
    }

    @Test func customBeatsAutomaticAndConflictsAreReported() {
        var list = cheets(3)
        let base: ModifierSet = [.control, .option, .command]
        // Cheet 3 claims cheet 1's automatic combo.
        list[2].hotkey = .custom(KeyCombo(keyCode: KeyCodes.one, modifiers: base))
        // Cheet 2 is disabled.
        list[1].hotkey = .disabled
        let plan = HotkeyResolver.resolve(cheets: list, settings: HotkeySettings())
        #expect(plan.cheetCombos[list[2].id]?.keyCode == KeyCodes.one)
        #expect(plan.cheetCombos[list[0].id] == nil)
        #expect(plan.cheetCombos[list[1].id] == nil)
        #expect(plan.conflicts[.showCheet(list[0].id)]?.keyCode == KeyCodes.one)
    }

    @Test func globalActionsWinAndBaseWithoutModifiersDisablesAuto() {
        var settings = HotkeySettings()
        settings.baseModifiers = [.shift]
        let plan = HotkeyResolver.resolve(cheets: cheets(3), settings: settings)
        #expect(plan.cheetCombos.isEmpty)
        #expect(plan.combo(for: .showPicker) != nil)
        #expect(plan.combo(for: .toggleLastCheet) != nil)
    }

    @Test func slotLabels() {
        #expect(HotkeyResolver.slotLabel(forIndex: 0) == "1")
        #expect(HotkeyResolver.slotLabel(forIndex: 9) == "0")
        #expect(HotkeyResolver.slotLabel(forIndex: 10) == nil)
    }
}

struct SearchTests {
    @Test func filterKeepsMatchingRowsAndWholeSections() throws {
        let cheet = SampleCheets.all()[1] // macOS Essentials
        let index = CheetSearchIndex(cheet: cheet)

        let screenshots = index.filter("screenshots")
        #expect(screenshots.map(\.title) == ["Screenshots"])
        #expect(screenshots[0].blocks == cheet.sections.first { $0.title == "Screenshots" }!.blocks)

        let trash = index.filter("trash")
        #expect(trash.map(\.title) == ["Finder"])
        guard case .table(let t) = trash[0].blocks[0] else { Issue.record(); return }
        #expect(t.rows.count == 1)

        #expect(index.filter("zzqx").isEmpty)
        #expect(index.filter("").count == cheet.sections.count)
    }

    @Test func multiTokenAndDiacritics() {
        let cheet = Cheet(title: "T", sections: [
            CheetSection(title: "Café", blocks: [.table(CheetTable(rows: [["⌘N", "New window"], ["⌘W", "Close window"]]))]),
        ])
        let index = CheetSearchIndex(cheet: cheet)
        #expect(index.filter("cafe").first?.blocks.count == 1)
        guard case .table(let t) = index.filter("close win").first?.blocks.first else { Issue.record(); return }
        #expect(t.rows == [["⌘W", "Close window"]])
    }
}

struct StorageTests {
    @Test func libraryAndSettingsPersist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(directory: dir)
        #expect(try store.loadCheets() == nil)

        var cheets = SampleCheets.all().map { cheet -> Cheet in
            var s = cheet
            s.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            s.updatedAt = s.createdAt
            return s
        }
        cheets[0].appearance = Appearance()
        cheets[1].hotkey = .custom(KeyCombo(keyCode: KeyCodes.k, modifiers: [.command, .shift]))
        try store.saveLibrary(Library(cheets: cheets))
        #expect(try store.loadLibrary() == Library(cheets: cheets))

        var settings = AppSettings()
        settings.appearance.fontSize = 17
        settings.hotkeys.baseModifiers = [.control, .shift]
        settings.branding.iconScheme = .classic
        settings.branding.showSplash = false
        try store.saveSettings(settings)
        #expect(store.loadSettings() == settings)
    }

    @Test func settingsDecodeMissingKeysWithDefaults() throws {
        let json = #"{"appearance": {"fontSize": 20}, "behavior": {"trigger": "toggle"}}"#
        let settings = ResilientJSON.decode(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        #expect(settings.appearance.fontSize == 20)
        #expect(settings.appearance.material == .hud)
        #expect(settings.behavior.trigger == .toggle)
        #expect(settings.hotkeys == HotkeySettings())
    }

    @Test func settingsFromBeforeIconSchemesUseCheeter() {
        let json = #"{"appearance": {"fontSize": 20}}"#
        let settings = ResilientJSON.decode(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        #expect(settings.branding == Branding())
        #expect(settings.branding.iconScheme == .cheeter)
        #expect(settings.branding.splashEnabled)
    }

    @Test func cheeterExtrasOnlyApplyToTheCheeterScheme() {
        var branding = Branding()
        branding.iconScheme = .classic
        #expect(!branding.splashEnabled)
        #expect(!branding.pickerMascotEnabled)

        branding.iconScheme = .cheeter
        #expect(branding.splashEnabled)
        #expect(branding.pickerMascotEnabled)

        branding.showSplash = false
        branding.showPickerMascot = false
        #expect(!branding.splashEnabled)
        #expect(!branding.pickerMascotEnabled)
    }

    @Test func normalizedRectRoundTrip() {
        let container = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let rect = CGRect(x: 300, y: 250, width: 500, height: 400)
        let n = NormalizedRect(rect: rect, in: container)
        #expect(n.denormalized(in: container) == rect)
    }
}

struct LegacyMigrationTests {
    @Test func preRenameFilesStillLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID()
        let library = #"{"version":1,"sheets":[{"id":"\#(id.uuidString)","title":"Old","sections":[{"title":"S","blocks":[{"type":"text","text":"hi"}]}]}]}"#
        let state = #"{"lastSheetID":"\#(id.uuidString)","sheets":{"\#(id.uuidString)":{"collapsedSections":[]}},"hasLaunchedBefore":true}"#
        let settings = #"{"layout":{"perSheetFrames":true,"anchor":"top"}}"#
        try Data(library.utf8).write(to: dir.appendingPathComponent("library.json"))
        try Data(state.utf8).write(to: dir.appendingPathComponent("state.json"))
        try Data(settings.utf8).write(to: dir.appendingPathComponent("settings.json"))

        let store = LibraryStore(directory: dir)
        #expect(try store.loadCheets()?.map(\.title) == ["Old"])
        let viewState = store.loadViewState()
        #expect(viewState.lastCheetID == id)
        #expect(viewState.cheets[id.uuidString] != nil)
        let loadedSettings = store.loadSettings()
        #expect(loadedSettings.layout.perCheetFrames)
        #expect(loadedSettings.layout.anchor == .top)
    }

    @Test func legacyDirectoryMovesOnce() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Cheat with Both Hands")
        let current = base.appendingPathComponent("Cheet with Both Hands")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("library.json"))

        #expect(LibraryStore.migrateLegacyDirectory(from: legacy, to: current))
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("library.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!LibraryStore.migrateLegacyDirectory(from: legacy, to: current))
    }
}
