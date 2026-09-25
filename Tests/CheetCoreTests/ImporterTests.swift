import XCTest
@testable import CheetCore

final class MarkdownImporterTests: XCTestCase {
    func testTitleSectionsTablesAndLists() throws {
        let md = """
        # Git Cheats

        Intro paragraph.

        ## Branches
        | Command | Does |
        |---|---|
        | `git switch -c x` | Create branch |
        | `git branch -d x` | Delete \\| remove |

        ### Remote
        - `git push -u origin HEAD` — push and track
        - `git fetch --prune` — prune

        ## Misc
        1. first
        2. second
            continued
        """
        let result = try CheetImporter.importCheet(md, options: ImportOptions(format: .markdown))
        let cheet = result.cheet
        XCTAssertEqual(cheet.title, "Git Cheats")
        XCTAssertEqual(cheet.sections.map(\.title), ["", "Branches", "Misc"])
        XCTAssertEqual(cheet.sections[0].blocks, [.text("Intro paragraph.")])

        guard case .table(let table) = cheet.sections[1].blocks[0] else { return XCTFail("expected table") }
        XCTAssertEqual(table.headers, ["Command", "Does"])
        XCTAssertEqual(table.rows[1], ["`git branch -d x`", "Delete | remove"])

        XCTAssertEqual(cheet.sections[1].blocks[1], .heading("Remote"))
        guard case .table(let kv) = cheet.sections[1].blocks[2] else { return XCTFail("key/value list should become a table") }
        XCTAssertNil(kv.headers)
        XCTAssertEqual(kv.rows[0], ["`git push -u origin HEAD`", "push and track"])

        guard case .list(let list) = cheet.sections[2].blocks[0] else { return XCTFail("expected list") }
        XCTAssertTrue(list.ordered)
        XCTAssertEqual(list.items, ["first", "second continued"])
    }

    func testNestedListsAndCode() throws {
        let md = """
        ## Setup
        - one
          - nested
        - two

        ```bash
        brew install thing
          indented
        ```
        """
        let cheet = try CheetImporter.importCheet(md, options: ImportOptions(format: .markdown, fallbackTitle: "Fallback")).cheet
        XCTAssertEqual(cheet.title, "Setup")
        let blocks = cheet.sections[0].blocks
        XCTAssertEqual(blocks[0], .list(ListBlock(items: ["one", "  nested", "two"])))
        XCTAssertEqual(blocks[1], .code(CodeBlock(code: "brew install thing\n  indented", language: "bash")))
    }

    func testMultipleH1BecomeSectionsAndFallbackTitle() throws {
        let md = "# One\ntext a\n# Two\ntext b"
        let result = try CheetImporter.importCheet(md, options: ImportOptions(fallbackTitle: "From File"))
        XCTAssertEqual(result.cheet.title, "From File")
        XCTAssertEqual(result.cheet.sections.map(\.title), ["One", "Two"])
    }

    func testSingleSectionWithSubheadingsIsSplit() throws {
        let md = "# T\n## Only\n### A\n- x\n### B\n- y"
        let cheet = try CheetImporter.importCheet(md).cheet
        XCTAssertEqual(cheet.sections.map(\.title), ["A", "B"])
    }

    func testExplicitTitleWins() throws {
        let cheet = try CheetImporter.importCheet("# Doc\n- a", options: ImportOptions(title: "Mine")).cheet
        XCTAssertEqual(cheet.title, "Mine")
    }

    func testSetextHeadings() throws {
        let cheet = try CheetImporter.importCheet("Title\n=====\n\nPart\n----\ncontent").cheet
        XCTAssertEqual(cheet.title, "Title")
        XCTAssertEqual(cheet.sections.map(\.title), ["Part"])
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try CheetImporter.importCheet("   \n ")) { error in
            XCTAssertEqual(error as? ImportError, .empty)
        }
    }
}

final class HTMLImporterTests: XCTestCase {
    func testTableWithKbdAndTitle() throws {
        let html = """
        <!doctype html><html><head><title>VS Code | Shortcuts</title><script>var x = "<h2>no</h2>";</script></head>
        <body><nav><a href="/">Home</a></nav>
        <main><h1>VS Code</h1>
        <section><h2>General</h2>
        <table><thead><tr><th>Keys</th><th>Action</th></tr></thead>
        <tbody>
        <tr><td><kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd></td><td>Command <b>palette</b></td></tr>
        <tr><td colspan="2">Editing</td></tr>
        <tr><td><kbd>Ctrl</kbd>+<kbd>X</kbd></td><td>Cut line_one *star*</td></tr>
        </tbody></table></section>
        <footer>© someone</footer></main></body></html>
        """
        let result = try CheetImporter.importCheet(html)
        XCTAssertEqual(result.detectedFormat, .html)
        let cheet = result.cheet
        XCTAssertEqual(cheet.title, "VS Code")
        XCTAssertEqual(cheet.sections.count, 1)
        XCTAssertEqual(cheet.sections[0].title, "General")

        let blocks = cheet.sections[0].blocks
        guard case .table(let first) = blocks[0] else { return XCTFail("expected table, got \(blocks)") }
        XCTAssertEqual(first.headers, ["Keys", "Action"])
        XCTAssertEqual(first.rows, [["`Ctrl`+`Shift`+`P`", "Command **palette**"]])
        XCTAssertEqual(blocks[1], .heading("Editing"))
        guard case .table(let second) = blocks[2] else { return XCTFail("expected second table") }
        XCTAssertEqual(second.rows[0][1], "Cut line\\_one \\*star\\*")
        XCTAssertEqual(InlineMarkdown.plainText(second.rows[0][1]), "Cut line_one *star*")
        XCTAssertFalse(cheet.sections.flatMap(\.blocks).contains(.text("© someone")))
    }

    func testFragmentListsDefinitionListsAndCode() throws {
        let html = """
        <h2>Motions</h2>
        <ul><li><code>w</code> next word</li><li><code>b</code> back a word</li></ul>
        <h2>Terms</h2>
        <dl><dt>HEAD</dt><dd>Current commit</dd><dt>Index</dt><dd>Staging area</dd></dl>
        <h2>Code</h2>
        <pre><code class="language-sh">echo hi
        echo there</code></pre>
        <p>See <a href="https://example.com/x">the docs</a>.</p>
        """
        let cheet = try CheetImporter.importCheet(html, options: ImportOptions(format: .html)).cheet
        XCTAssertEqual(cheet.sections.map(\.title), ["Motions", "Terms", "Code"])
        XCTAssertEqual(cheet.sections[0].blocks, [.table(CheetTable(rows: [["`w`", "next word"], ["`b`", "back a word"]]))])
        XCTAssertEqual(cheet.sections[1].blocks, [.table(CheetTable(rows: [["HEAD", "Current commit"], ["Index", "Staging area"]]))])
        XCTAssertEqual(cheet.sections[2].blocks[0], .code(CodeBlock(code: "echo hi\necho there", language: "sh")))
        XCTAssertEqual(cheet.sections[2].blocks[1], .text("See [the docs](https://example.com/x)."))
    }

    func testNestedHTMLLists() throws {
        let html = "<ul><li>Top<ul><li>Child</li></ul></li><li>Next</li></ul>"
        let cheet = try CheetImporter.importCheet(html, options: ImportOptions(format: .html, fallbackTitle: "X")).cheet
        XCTAssertEqual(cheet.sections[0].blocks, [.list(ListBlock(items: ["Top", "  Child", "Next"]))])
    }
}

final class DelimitedImporterTests: XCTestCase {
    func testCSVWithQuotesHeaderAndSections() throws {
        let csv = #"""
        Shortcut,Action
        Navigation
        "Ctrl+G","Go to line, quickly"
        Ctrl+P,Quick open
        Editing
        Ctrl+/,"Toggle ""comment"""
        """#
        let result = try CheetImporter.importCheet(csv, options: ImportOptions(fallbackTitle: "Editor"))
        XCTAssertEqual(result.detectedFormat, .delimited)
        let cheet = result.cheet
        XCTAssertEqual(cheet.title, "Editor")
        XCTAssertEqual(cheet.sections.map(\.title), ["Navigation", "Editing"])
        guard case .table(let nav) = cheet.sections[0].blocks[0] else { return XCTFail() }
        XCTAssertEqual(nav.headers, ["Shortcut", "Action"])
        XCTAssertEqual(nav.rows, [["Ctrl+G", "Go to line, quickly"], ["Ctrl+P", "Quick open"]])
        guard case .table(let edit) = cheet.sections[1].blocks[0] else { return XCTFail() }
        XCTAssertEqual(edit.rows, [["Ctrl+/", "Toggle \"comment\""]])
    }

    func testTSVGroupingColumn() throws {
        let tsv = "Category\tKey\tAction\nFile\t⌘N\tNew\nFile\t⌘O\tOpen\nEdit\t⌘Z\tUndo\n"
        let cheet = try CheetImporter.importCheet(tsv).cheet
        XCTAssertEqual(cheet.sections.map(\.title), ["File", "Edit"])
        guard case .table(let file) = cheet.sections[0].blocks[0] else { return XCTFail() }
        XCTAssertEqual(file.headers, ["Key", "Action"])
        XCTAssertEqual(file.rows, [["⌘N", "New"], ["⌘O", "Open"]])
    }

    func testAlignedColumnsWithoutHeader() throws {
        let text = "Ctrl+A    Select all\nCtrl+C    Copy\nCtrl+V    Paste the clipboard\n"
        let result = try CheetImporter.importCheet(text, options: ImportOptions(fallbackTitle: "Basics"))
        XCTAssertEqual(result.detectedFormat, .delimited)
        guard case .table(let table) = result.cheet.sections[0].blocks[0] else { return XCTFail() }
        XCTAssertNil(table.headers)
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[2], ["Ctrl+V", "Paste the clipboard"])
    }

    func testOverflowCellsMergeIntoLastColumn() {
        let rows = [["a", "b", "c", "d"]]
        XCTAssertEqual(DelimitedImporter.fit(rows[0], to: 2, delimiter: .comma), ["a", "b, c, d"])
    }
}

final class JSONImporterTests: XCTestCase {
    func testArrayOfObjectsKeepsKeyOrder() throws {
        let json = #"[{"key": "⌘C", "action": "Copy"}, {"key": "⌘V", "action": "Paste"}]"#
        let result = try CheetImporter.importCheet(json, options: ImportOptions(fallbackTitle: "Clip"))
        XCTAssertEqual(result.detectedFormat, .json)
        guard case .table(let table) = result.cheet.sections[0].blocks[0] else { return XCTFail() }
        XCTAssertEqual(table.headers, ["key", "action"])
        XCTAssertEqual(table.rows, [["⌘C", "Copy"], ["⌘V", "Paste"]])
    }

    func testObjectOfSections() throws {
        let json = #"{"Files": {"⌘N": "New", "⌘O": "Open"}, "Tips": ["one", "two"]}"#
        let cheet = try CheetImporter.importCheet(json, options: ImportOptions(fallbackTitle: "J")).cheet
        XCTAssertEqual(cheet.sections.map(\.title), ["Files", "Tips"])
        XCTAssertEqual(cheet.sections[1].blocks, [.list(ListBlock(items: ["one", "two"]))])
    }

    func testOwnCheetFormatRoundTrips() throws {
        let original = SampleCheets.all()[0]
        let data = try LibraryStore.encodeCheet(original)
        let cheet = try CheetImporter.importCheet(String(decoding: data, as: UTF8.self)).cheet
        XCTAssertEqual(cheet.title, original.title)
        XCTAssertEqual(cheet.sections.map(\.blocks), original.sections.map(\.blocks))
    }
}

final class DetectionTests: XCTestCase {
    func testDetectsFormats() {
        XCTAssertEqual(ImportFormat.detect("# Hi\n- a"), .markdown)
        XCTAssertEqual(ImportFormat.detect("<table><tr><td>a</td><td>b</td></tr></table>"), .html)
        XCTAssertEqual(ImportFormat.detect("a,b\nc,d\ne,f"), .delimited)
        XCTAssertEqual(ImportFormat.detect("a\tb\nc\td"), .delimited)
        XCTAssertEqual(ImportFormat.detect(#"{"a": 1}"#), .json)
        XCTAssertEqual(ImportFormat.detect("| a | b |\n|---|---|\n| 1 | 2 |"), .markdown)
        XCTAssertEqual(ImportFormat.detect("Just a sentence, with a comma."), .markdown)
    }

    func testTitleFromFileName() {
        XCTAssertEqual(CheetImporter.title(fromFileName: "git-cheat_sheet.md"), "Git Cheat Sheet")
        XCTAssertEqual(CheetImporter.title(fromFileName: "VSCode Keys.csv"), "VSCode Keys")
    }
}

final class ExportRoundTripTests: XCTestCase {
    func testSamplesRoundTripThroughMarkdown() throws {
        for sample in SampleCheets.all() {
            let markdown = MarkdownExporter.markdown(for: sample)
            let reimported = try CheetImporter.importCheet(markdown, options: ImportOptions(format: .markdown)).cheet
            XCTAssertEqual(reimported.title, sample.title)
            XCTAssertEqual(reimported.sections.map(\.title), sample.sections.map(\.title), sample.title)
            XCTAssertEqual(reimported.sections.map(\.blocks), sample.sections.map(\.blocks), sample.title)
        }
    }

    func testSamplesAreNonTrivial() {
        let samples = SampleCheets.all()
        XCTAssertEqual(samples.count, 4)
        for sample in samples {
            XCTAssertGreaterThan(sample.sections.count, 2, sample.title)
            XCTAssertGreaterThan(sample.entryCount, 10, sample.title)
        }
    }
}
