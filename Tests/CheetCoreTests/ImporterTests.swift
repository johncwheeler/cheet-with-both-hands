import Foundation
import Testing
@testable import CheetCore

struct MarkdownImporterTests {
    @Test func titleSectionsTablesAndLists() throws {
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
        #expect(cheet.title == "Git Cheats")
        #expect(cheet.sections.map(\.title) == ["", "Branches", "Misc"])
        #expect(cheet.sections[0].blocks == [.text("Intro paragraph.")])

        guard case .table(let table) = cheet.sections[1].blocks[0] else { Issue.record("expected table"); return }
        #expect(table.headers == ["Command", "Does"])
        #expect(table.rows[1] == ["`git branch -d x`", "Delete | remove"])

        #expect(cheet.sections[1].blocks[1] == .heading("Remote"))
        guard case .table(let kv) = cheet.sections[1].blocks[2] else { Issue.record("key/value list should become a table"); return }
        #expect(kv.headers == nil)
        #expect(kv.rows[0] == ["`git push -u origin HEAD`", "push and track"])

        guard case .list(let list) = cheet.sections[2].blocks[0] else { Issue.record("expected list"); return }
        #expect(list.ordered)
        #expect(list.items == ["first", "second continued"])
    }

    @Test func nestedListsAndCode() throws {
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
        #expect(cheet.title == "Setup")
        let blocks = cheet.sections[0].blocks
        #expect(blocks[0] == .list(ListBlock(items: ["one", "  nested", "two"])))
        #expect(blocks[1] == .code(CodeBlock(code: "brew install thing\n  indented", language: "bash")))
    }

    @Test func multipleH1BecomeSectionsAndFallbackTitle() throws {
        let md = "# One\ntext a\n# Two\ntext b"
        let result = try CheetImporter.importCheet(md, options: ImportOptions(fallbackTitle: "From File"))
        #expect(result.cheet.title == "From File")
        #expect(result.cheet.sections.map(\.title) == ["One", "Two"])
    }

    @Test func singleSectionWithSubheadingsIsSplit() throws {
        let md = "# T\n## Only\n### A\n- x\n### B\n- y"
        let cheet = try CheetImporter.importCheet(md).cheet
        #expect(cheet.sections.map(\.title) == ["A", "B"])
    }

    @Test func explicitTitleWins() throws {
        let cheet = try CheetImporter.importCheet("# Doc\n- a", options: ImportOptions(title: "Mine")).cheet
        #expect(cheet.title == "Mine")
    }

    @Test func setextHeadings() throws {
        let cheet = try CheetImporter.importCheet("Title\n=====\n\nPart\n----\ncontent").cheet
        #expect(cheet.title == "Title")
        #expect(cheet.sections.map(\.title) == ["Part"])
    }

    @Test func emptyInputThrows() {
        #expect(throws: ImportError.empty) {
            try CheetImporter.importCheet("   \n ")
        }
    }
}

struct HTMLImporterTests {
    @Test func tableWithKbdAndTitle() throws {
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
        #expect(result.detectedFormat == .html)
        let cheet = result.cheet
        #expect(cheet.title == "VS Code")
        #expect(cheet.sections.count == 1)
        #expect(cheet.sections[0].title == "General")

        let blocks = cheet.sections[0].blocks
        guard case .table(let first) = blocks[0] else { Issue.record("expected table, got \(blocks)"); return }
        #expect(first.headers == ["Keys", "Action"])
        #expect(first.rows == [["`Ctrl`+`Shift`+`P`", "Command **palette**"]])
        #expect(blocks[1] == .heading("Editing"))
        guard case .table(let second) = blocks[2] else { Issue.record("expected second table"); return }
        #expect(second.rows[0][1] == "Cut line\\_one \\*star\\*")
        #expect(InlineMarkdown.plainText(second.rows[0][1]) == "Cut line_one *star*")
        #expect(!cheet.sections.flatMap(\.blocks).contains(.text("© someone")))
    }

    @Test func fragmentListsDefinitionListsAndCode() throws {
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
        #expect(cheet.sections.map(\.title) == ["Motions", "Terms", "Code"])
        #expect(cheet.sections[0].blocks == [.table(CheetTable(rows: [["`w`", "next word"], ["`b`", "back a word"]]))])
        #expect(cheet.sections[1].blocks == [.table(CheetTable(rows: [["HEAD", "Current commit"], ["Index", "Staging area"]]))])
        #expect(cheet.sections[2].blocks[0] == .code(CodeBlock(code: "echo hi\necho there", language: "sh")))
        #expect(cheet.sections[2].blocks[1] == .text("See [the docs](https://example.com/x)."))
    }

    @Test func nestedHTMLLists() throws {
        let html = "<ul><li>Top<ul><li>Child</li></ul></li><li>Next</li></ul>"
        let cheet = try CheetImporter.importCheet(html, options: ImportOptions(format: .html, fallbackTitle: "X")).cheet
        #expect(cheet.sections[0].blocks == [.list(ListBlock(items: ["Top", "  Child", "Next"]))])
    }
}

struct DelimitedImporterTests {
    @Test func cSVWithQuotesHeaderAndSections() throws {
        let csv = #"""
        Shortcut,Action
        Navigation
        "Ctrl+G","Go to line, quickly"
        Ctrl+P,Quick open
        Editing
        Ctrl+/,"Toggle ""comment"""
        """#
        let result = try CheetImporter.importCheet(csv, options: ImportOptions(fallbackTitle: "Editor"))
        #expect(result.detectedFormat == .delimited)
        let cheet = result.cheet
        #expect(cheet.title == "Editor")
        #expect(cheet.sections.map(\.title) == ["Navigation", "Editing"])
        guard case .table(let nav) = cheet.sections[0].blocks[0] else { Issue.record(); return }
        #expect(nav.headers == ["Shortcut", "Action"])
        #expect(nav.rows == [["Ctrl+G", "Go to line, quickly"], ["Ctrl+P", "Quick open"]])
        guard case .table(let edit) = cheet.sections[1].blocks[0] else { Issue.record(); return }
        #expect(edit.rows == [["Ctrl+/", "Toggle \"comment\""]])
    }

    @Test func tSVGroupingColumn() throws {
        let tsv = "Category\tKey\tAction\nFile\t⌘N\tNew\nFile\t⌘O\tOpen\nEdit\t⌘Z\tUndo\n"
        let cheet = try CheetImporter.importCheet(tsv).cheet
        #expect(cheet.sections.map(\.title) == ["File", "Edit"])
        guard case .table(let file) = cheet.sections[0].blocks[0] else { Issue.record(); return }
        #expect(file.headers == ["Key", "Action"])
        #expect(file.rows == [["⌘N", "New"], ["⌘O", "Open"]])
    }

    @Test func alignedColumnsWithoutHeader() throws {
        let text = "Ctrl+A    Select all\nCtrl+C    Copy\nCtrl+V    Paste the clipboard\n"
        let result = try CheetImporter.importCheet(text, options: ImportOptions(fallbackTitle: "Basics"))
        #expect(result.detectedFormat == .delimited)
        guard case .table(let table) = result.cheet.sections[0].blocks[0] else { Issue.record(); return }
        #expect(table.headers == nil)
        #expect(table.rows.count == 3)
        #expect(table.rows[2] == ["Ctrl+V", "Paste the clipboard"])
    }

    @Test func overflowCellsMergeIntoLastColumn() {
        let rows = [["a", "b", "c", "d"]]
        #expect(DelimitedImporter.fit(rows[0], to: 2, delimiter: .comma) == ["a", "b, c, d"])
    }
}

struct JSONImporterTests {
    @Test func arrayOfObjectsKeepsKeyOrder() throws {
        let json = #"[{"key": "⌘C", "action": "Copy"}, {"key": "⌘V", "action": "Paste"}]"#
        let result = try CheetImporter.importCheet(json, options: ImportOptions(fallbackTitle: "Clip"))
        #expect(result.detectedFormat == .json)
        guard case .table(let table) = result.cheet.sections[0].blocks[0] else { Issue.record(); return }
        #expect(table.headers == ["key", "action"])
        #expect(table.rows == [["⌘C", "Copy"], ["⌘V", "Paste"]])
    }

    @Test func objectOfSections() throws {
        let json = #"{"Files": {"⌘N": "New", "⌘O": "Open"}, "Tips": ["one", "two"]}"#
        let cheet = try CheetImporter.importCheet(json, options: ImportOptions(fallbackTitle: "J")).cheet
        #expect(cheet.sections.map(\.title) == ["Files", "Tips"])
        #expect(cheet.sections[1].blocks == [.list(ListBlock(items: ["one", "two"]))])
    }

    @Test func ownCheetFormatRoundTrips() throws {
        let original = SampleCheets.all()[0]
        let data = try LibraryStore.encodeCheet(original)
        let cheet = try CheetImporter.importCheet(String(decoding: data, as: UTF8.self)).cheet
        #expect(cheet.title == original.title)
        #expect(cheet.sections.map(\.blocks) == original.sections.map(\.blocks))
    }
}

struct DetectionTests {
    @Test func detectsFormats() {
        #expect(ImportFormat.detect("# Hi\n- a") == .markdown)
        #expect(ImportFormat.detect("<table><tr><td>a</td><td>b</td></tr></table>") == .html)
        #expect(ImportFormat.detect("a,b\nc,d\ne,f") == .delimited)
        #expect(ImportFormat.detect("a\tb\nc\td") == .delimited)
        #expect(ImportFormat.detect(#"{"a": 1}"#) == .json)
        #expect(ImportFormat.detect("| a | b |\n|---|---|\n| 1 | 2 |") == .markdown)
        #expect(ImportFormat.detect("Just a sentence, with a comma.") == .markdown)
    }

    @Test func titleFromFileName() {
        #expect(CheetImporter.title(fromFileName: "git-cheat_sheet.md") == "Git Cheat Sheet")
        #expect(CheetImporter.title(fromFileName: "VSCode Keys.csv") == "VSCode Keys")
    }
}

struct ExportRoundTripTests {
    @Test func samplesRoundTripThroughMarkdown() throws {
        for sample in SampleCheets.all() {
            let markdown = MarkdownExporter.markdown(for: sample)
            let reimported = try CheetImporter.importCheet(markdown, options: ImportOptions(format: .markdown)).cheet
            #expect(reimported.title == sample.title)
            #expect(reimported.sections.map(\.title) == sample.sections.map(\.title), "\(sample.title)")
            #expect(reimported.sections.map(\.blocks) == sample.sections.map(\.blocks), "\(sample.title)")
        }
    }

    @Test func samplesAreNonTrivial() {
        let samples = SampleCheets.all()
        #expect(samples.count == 4)
        for sample in samples {
            #expect(sample.sections.count > 2, "\(sample.title)")
            #expect(sample.entryCount > 10, "\(sample.title)")
        }
    }
}
