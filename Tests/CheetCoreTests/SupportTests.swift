import XCTest
@testable import CheetCore

final class KeyCapParserTests: XCTestCase {
    func testRecognisesCommonNotations() {
        XCTAssertEqual(KeyCapParser.parse("Ctrl+Shift+P"), [.chord(["Ctrl", "Shift", "P"])])
        XCTAssertEqual(KeyCapParser.parse("⌘⇧P"), [.chord(["⌘", "⇧", "P"])])
        XCTAssertEqual(KeyCapParser.parse("⌘K ⌘S"), [.chord(["⌘", "K"]), .chord(["⌘", "S"])])
        XCTAssertEqual(KeyCapParser.parse("`Ctrl`+`C`"), [.chord(["Ctrl", "C"])])
        XCTAssertEqual(KeyCapParser.parse("C-x C-s"), [.chord(["Ctrl", "x"]), .chord(["Ctrl", "s"])])
        XCTAssertEqual(KeyCapParser.parse("⇧⌘4 then Space"), [.chord(["⇧", "⌘", "4"]), .separator("then"), .chord(["Space"])])
        XCTAssertEqual(KeyCapParser.parse("⌥← / ⌥→"), [.chord(["⌥", "←"]), .separator("/"), .chord(["⌥", "→"])])
        XCTAssertEqual(KeyCapParser.parse("Ctrl++"), [.chord(["Ctrl", "+"])])
        XCTAssertEqual(KeyCapParser.parse("Cmd-Shift-P"), [.chord(["Cmd", "Shift", "P"])])
        XCTAssertEqual(KeyCapParser.parse("F5"), [.chord(["F5"])])
        XCTAssertEqual(KeyCapParser.parse("`Ctrl` + `Alt` + `Del`"), [.chord(["Ctrl", "Alt", "Del"])])
        XCTAssertEqual(KeyCapParser.parse("Ctrl + C"), [.chord(["Ctrl", "C"])])
        XCTAssertEqual(KeyCapParser.parse("⌃⌥⌘/"), [.chord(["⌃", "⌥", "⌘", "/"])])
        XCTAssertEqual(KeyCapParser.parse("⌘`"), [.chord(["⌘", "`"])])
        XCTAssertEqual(KeyCapParser.parse("⌘,"), [.chord(["⌘", ","])])
        XCTAssertEqual(KeyCapParser.parse("⌘+ / ⌘- / ⌘0"), [.chord(["⌘", "+"]), .separator("/"), .chord(["⌘", "-"]), .separator("/"), .chord(["⌘", "0"])])
        XCTAssertEqual(KeyCapParser.parse("⌘+K"), [.chord(["⌘", "K"])])
        XCTAssertEqual(KeyCapParser.parse("⌘1 … ⌘4"), [.chord(["⌘", "1"]), .separator("…"), .chord(["⌘", "4"])])
        XCTAssertEqual(KeyCapParser.parse("⌘9, ⌘0"), [.chord(["⌘", "9"]), .separator(","), .chord(["⌘", "0"])])
        XCTAssertEqual(KeyCapParser.parse("Ctrl+W s"), [.chord(["Ctrl", "W"]), .chord(["s"])])
    }

    func testRejectsProse() {
        XCTAssertNil(KeyCapParser.parse("Show the command palette"))
        XCTAssertNil(KeyCapParser.parse("`dd`"))
        XCTAssertNil(KeyCapParser.parse("`git status`"))
        XCTAssertNil(KeyCapParser.parse("a b c"))
        XCTAssertNil(KeyCapParser.parse("Add ⌃"))
        XCTAssertNil(KeyCapParser.parse("Scroll"))
        XCTAssertNil(KeyCapParser.parse("^"), "a lone caret is not Control")
        XCTAssertEqual(KeyCapParser.parse("^C"), [.chord(["Ctrl", "C"])])
        XCTAssertNil(KeyCapParser.parse("Drag"))
        XCTAssertEqual(KeyCapParser.parse("Cmd+Click"), [.chord(["Cmd", "Click"])])
        XCTAssertNil(KeyCapParser.parse("⌘§•"))
        XCTAssertNil(KeyCapParser.parse(""))
    }

    func testDisplayStyles() {
        XCTAssertEqual(KeyCapParser.display(["Ctrl", "Shift", "p"], style: .symbols), ["⌃", "⇧", "P"])
        XCTAssertEqual(KeyCapParser.display(["⌘", "⌥", "Esc"], style: .names), ["Cmd", "Opt", "Esc"])
        XCTAssertEqual(KeyCapParser.display(["s"], style: .symbols), ["s"])
        XCTAssertEqual(KeyCapParser.compactSymbolLabel(["⌘", "⇧", "⌃", "P"]), "⌃⇧⌘P")
        XCTAssertEqual(KeyCapParser.compactSymbolLabel(["⌘", "Space"]), "⌘ Space")
    }
}

final class HotkeyResolverTests: XCTestCase {
    private func cheets(_ n: Int) -> [Cheet] {
        (0..<n).map { Cheet(title: "S\($0)", sections: []) }
    }

    func testAutomaticNumberingCoversTenSlots() {
        let list = cheets(12)
        let plan = HotkeyResolver.resolve(cheets: list, settings: HotkeySettings())
        XCTAssertEqual(plan.cheetCombos.count, 10)
        XCTAssertEqual(plan.cheetCombos[list[0].id]?.keyCode, KeyCodes.one)
        XCTAssertEqual(plan.cheetCombos[list[9].id]?.keyCode, KeyCodes.zero)
        XCTAssertNil(plan.cheetCombos[list[10].id])
        XCTAssertEqual(plan.cheetCombos[list[0].id]?.modifiers, [.control, .option, .command])
    }

    func testCustomBeatsAutomaticAndConflictsAreReported() {
        var list = cheets(3)
        let base: ModifierSet = [.control, .option, .command]
        // Cheet 3 claims cheet 1's automatic combo.
        list[2].hotkey = .custom(KeyCombo(keyCode: KeyCodes.one, modifiers: base))
        // Cheet 2 is disabled.
        list[1].hotkey = .disabled
        let plan = HotkeyResolver.resolve(cheets: list, settings: HotkeySettings())
        XCTAssertEqual(plan.cheetCombos[list[2].id]?.keyCode, KeyCodes.one)
        XCTAssertNil(plan.cheetCombos[list[0].id])
        XCTAssertNil(plan.cheetCombos[list[1].id])
        XCTAssertEqual(plan.conflicts[.showCheet(list[0].id)]?.keyCode, KeyCodes.one)
    }

    func testGlobalActionsWinAndBaseWithoutModifiersDisablesAuto() {
        var settings = HotkeySettings()
        settings.baseModifiers = [.shift]
        let plan = HotkeyResolver.resolve(cheets: cheets(3), settings: settings)
        XCTAssertTrue(plan.cheetCombos.isEmpty)
        XCTAssertNotNil(plan.combo(for: .showPicker))
        XCTAssertNotNil(plan.combo(for: .toggleLastCheet))
    }

    func testSlotLabels() {
        XCTAssertEqual(HotkeyResolver.slotLabel(forIndex: 0), "1")
        XCTAssertEqual(HotkeyResolver.slotLabel(forIndex: 9), "0")
        XCTAssertNil(HotkeyResolver.slotLabel(forIndex: 10))
    }
}

final class SearchTests: XCTestCase {
    func testFilterKeepsMatchingRowsAndWholeSections() throws {
        let cheet = SampleCheets.all()[1] // macOS Essentials
        let index = CheetSearchIndex(cheet: cheet)

        let screenshots = index.filter("screenshots")
        XCTAssertEqual(screenshots.map(\.title), ["Screenshots"])
        XCTAssertEqual(screenshots[0].blocks, cheet.sections.first { $0.title == "Screenshots" }!.blocks)

        let trash = index.filter("trash")
        XCTAssertEqual(trash.map(\.title), ["Finder"])
        guard case .table(let t) = trash[0].blocks[0] else { return XCTFail() }
        XCTAssertEqual(t.rows.count, 1)

        XCTAssertTrue(index.filter("zzqx").isEmpty)
        XCTAssertEqual(index.filter("").count, cheet.sections.count)
    }

    func testMultiTokenAndDiacritics() {
        let cheet = Cheet(title: "T", sections: [
            CheetSection(title: "Café", blocks: [.table(CheetTable(rows: [["⌘N", "New window"], ["⌘W", "Close window"]]))]),
        ])
        let index = CheetSearchIndex(cheet: cheet)
        XCTAssertEqual(index.filter("cafe").first?.blocks.count, 1)
        guard case .table(let t) = index.filter("close win").first?.blocks.first else { return XCTFail() }
        XCTAssertEqual(t.rows, [["⌘W", "Close window"]])
    }
}

final class StorageTests: XCTestCase {
    func testLibraryAndSettingsPersist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(directory: dir)
        XCTAssertNil(try store.loadCheets())

        var cheets = SampleCheets.all().map { cheet -> Cheet in
            var s = cheet
            s.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            s.updatedAt = s.createdAt
            return s
        }
        cheets[0].appearance = Appearance()
        cheets[1].hotkey = .custom(KeyCombo(keyCode: KeyCodes.k, modifiers: [.command, .shift]))
        try store.saveCheets(cheets)
        XCTAssertEqual(try store.loadCheets(), cheets)

        var settings = AppSettings()
        settings.appearance.fontSize = 17
        settings.hotkeys.baseModifiers = [.control, .shift]
        try store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings(), settings)
    }

    func testSettingsDecodeMissingKeysWithDefaults() throws {
        let json = #"{"appearance": {"fontSize": 20}, "behavior": {"trigger": "toggle"}}"#
        let settings = ResilientJSON.decode(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        XCTAssertEqual(settings.appearance.fontSize, 20)
        XCTAssertEqual(settings.appearance.material, .hud)
        XCTAssertEqual(settings.behavior.trigger, .toggle)
        XCTAssertEqual(settings.hotkeys, HotkeySettings())
    }

    func testNormalizedRectRoundTrip() {
        let container = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let rect = CGRect(x: 300, y: 250, width: 500, height: 400)
        let n = NormalizedRect(rect: rect, in: container)
        XCTAssertEqual(n.denormalized(in: container), rect)
    }
}

final class LegacyMigrationTests: XCTestCase {
    func testPreRenameFilesStillLoad() throws {
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
        XCTAssertEqual(try store.loadCheets()?.map(\.title), ["Old"])
        let viewState = store.loadViewState()
        XCTAssertEqual(viewState.lastCheetID, id)
        XCTAssertNotNil(viewState.cheets[id.uuidString])
        let loadedSettings = store.loadSettings()
        XCTAssertTrue(loadedSettings.layout.perCheetFrames)
        XCTAssertEqual(loadedSettings.layout.anchor, .top)
    }

    func testLegacyDirectoryMovesOnce() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Cheat with Both Hands")
        let current = base.appendingPathComponent("Cheet with Both Hands")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("library.json"))

        XCTAssertTrue(LibraryStore.migrateLegacyDirectory(from: legacy, to: current))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("library.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(LibraryStore.migrateLegacyDirectory(from: legacy, to: current))
    }
}
