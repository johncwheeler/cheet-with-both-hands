import Foundation
import Testing
@testable import CheetCore

/// Fixtures are hand-written to mirror Cheatography's markup structure (no site content is copied).
enum Fixtures {
    static let cheatSheetPage = """
    <!doctype html><html><head>
    <title>Widget Tricks Cheat Sheet by sam - Cheatography</title>
    <meta property="og:title" content="Widget Tricks Cheat Sheet"/>
    <meta property="og:url" content="https://cheatography.com/sam/cheat-sheets/widget-tricks/"/>
    <meta name="description" content="Handy widget tricks &amp; shortcuts."/>
    <style>.commentblock { color: red }</style>
    </head><body>
    <h1><span itemprop="author" itemscope><a href="/sam/"><span itemprop="name">sam</span></a></span></h1>
    <article>
    <table class="cheat_sheet_output"><tr>
    <td class="cheat_sheet_output_column_1">
      <section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Basics</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_twocol">
          <tr><td class="cheat_sheet_output_cell_1"><div>Ctrl+W</div></td><td class="cheat_sheet_output_cell_2"><div>Wiggle the <strong>widget</strong></div></td></tr>
          <tr><td class="cheat_sheet_output_cell_1"><div>Ctrl+S</div></td><td class="cheat_sheet_output_cell_2"><div>Spin&#173;ning</div></td></tr>
          <tr><td class="cheat_sheet_output_cell_1" colspan="2"><div>Ctrl+Q</div></td></tr>
        </table><div class="cheat_sheet_note"><div>Works in every mode.</div></div></div>
      </section>
      <section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Pairs</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_fourcol">
          <tr><td class="cheat_sheet_output_cell_1"><div>a</div></td><td class="cheat_sheet_output_cell_2"><div>alpha</div></td>
              <td class="cheat_sheet_output_cell_3"><div>b</div></td><td class="cheat_sheet_output_cell_4"><div>beta</div></td></tr>
        </table></div>
      </section>
    </td>
    <td class="cheat_sheet_output_column_2">
      <section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Options</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_onecol">
          <tr><td class="cheat_sheet_output_cell_1"><div>verbose</div></td></tr>
          <tr><td class="cheat_sheet_output_cell_1"><div>quiet</div></td></tr>
        </table></div>
      </section>
      <section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Loop</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_text">
          <tr><td class="cheat_sheet_output_cell_1"><div><strong>While</strong><br />while x:<br />&nbsp;&nbsp;step()</div></td></tr>
        </table></div>
      </section>
      <section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Install</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_code">
          <tr><td class="cheat_sheet_output_cell_1"><pre><code>$ widget install
    $ widget run</code></pre></td></tr>
        </table></div>
      </section>
    </td></tr></table>
    </article>
    <div class="commentblock"><p class="commentext">Nice one!</p></div>
    </body></html>
    """

    static func listingRow(id: Int, slug: String, title: String, kind: String = "Cheat Sheet", author: String, rating: String? = nil) -> String {
        """
        <div itemscope itemtype="http://schema.org/CreativeWork" id="cheat_sheet_\(id)" class="cheat_sheet_row altrow">
        <div class="triptych1"><a class="lazy imagelink" data-original="//media.cheatography.com/storage/thumb/\(author)_\(slug).400.jpg" href="/\(author)/cheat-sheets/\(slug)/"></a>
        <div><span class="page_count"><i class="fa fa-fw fa-book"></i>2 Pages</span></div>
        <div>\(rating.map { "<!-- Average: \($0) --><i class=\"fa fa-star\"></i> &nbsp; (12)" } ?? "")</div></div>
        <div class="triptychdblr"><div><strong><a href="/\(author)/cheat-sheets/\(slug)/" itemprop="url"><span itemprop="name">\(title) <span style="font-weight: normal; font-size: 0.9em; opacity: 0.8;">\(kind)</span></span></a></strong>
        <div class="" style="line-height: 2; padding: 0;"><div style="padding: 5px 0 15px;">About \(title) &amp; more.</div>
        <div><span><a href="/\(author)/" class="user_hover">\(author)</a></span></div>
        <div><i class="fa fa-fw fa-calendar second-list" date-last-update="2020-01-01"></i>1 Jan 19, updated 1 Jan 20</div>
        <div><i class="fa fa-fw fa-tag"></i><a href="/tag/widgets/cheat-sheets/">widgets</a>, <a href="/tag/tools/cheat-sheets/">tools</a></div>
        </div></div></div><div class="clear"></div></div>
        """
    }

    static var listingPage: String {
        """
        <html><head><base href="https://cheatography.com/"></head><body>
        <h2>2 Widget Cheat Sheets</h2>
        \(listingRow(id: 1, slug: "widget-tricks", title: "Widget Tricks Cheat Sheet", author: "sam", rating: "4.5"))
        \(listingRow(id: 2, slug: "gadget-keys", title: "Gadget Keys", kind: "Keyboard Shortcuts", author: "lee"))
        <a class="next" href="tag/widgets/2">Next &#187;</a>
        <h2>Top Tags in Programming</h2> <ul> <li><a href="/tag/python/">Python</a> (183)</li><li><a href="/tag/git/">Git</a> (77)</li> </ul>
        <div class="biptychl"> <h2>Latest Cheat Sheet</h2>
        \(listingRow(id: 3, slug: "sidebar-thing", title: "Sidebar Thing", author: "zed"))
        </div></body></html>
        """
    }
}

struct CheatographyExtractorTests {
    @Test func extractsBlocksMetadataAndSkipsComments() {
        #expect(CheatographyExtractor.canHandle(html: Fixtures.cheatSheetPage))
        let doc = WebExtractor.extract(text: Fixtures.cheatSheetPage, url: URL(string: "https://cheatography.com/sam/cheat-sheets/widget-tricks/"))
        #expect(doc.extractorName == "Cheatography")
        #expect(doc.title == "Widget Tricks")
        #expect(doc.author == "sam")
        #expect(doc.summary == "Handy widget tricks & shortcuts.")
        #expect(doc.attribution == "by sam · Cheatography")
        #expect(doc.sections.map(\.title) == ["Basics", "Pairs", "Options", "Loop", "Install"])

        let basics = doc.sections[0].blocks
        #expect(basics[0] == .table(CheetTable(rows: [["Ctrl+W", "Wiggle the **widget**"], ["Ctrl+S", "Spinning"], ["Ctrl+Q", ""]])))
        #expect(basics[1] == .text("Works in every mode."))
        #expect(doc.sections[1].blocks == [.table(CheetTable(rows: [["a", "alpha"], ["b", "beta"]]))])
        #expect(doc.sections[2].blocks == [.list(ListBlock(items: ["verbose", "quiet"]))])
        #expect(doc.sections[3].blocks == [.text("**While**\nwhile x:\nstep()")])
        #expect(doc.sections[4].blocks == [.code(CodeBlock(code: "$ widget install\n$ widget run"))])
        #expect(!doc.sections.flatMap(\.blocks).contains(.text("Nice one!")))
    }

    @Test func selectionBuildsCheet() {
        let doc = WebExtractor.extract(text: Fixtures.cheatSheetPage, url: nil)
        var selection = ElementSelection()
        selection.setSection(doc.sections[2], included: false)          // drop "Options"
        selection.setBlock(1, in: doc.sections[0], included: false)       // drop the note in "Basics"
        #expect(selection.state(of: doc.sections[0]) == .mixed)
        #expect(selection.state(of: doc.sections[2]) == .off)

        let cheet = doc.cheet(selection: selection, title: "Mine")
        #expect(cheet.title == "Mine")
        #expect(cheet.sections.map(\.title) == ["Basics", "Pairs", "Loop", "Install"])
        #expect(cheet.sections[0].blocks.count == 1)
        #expect(cheet.source?.attribution == "by sam · Cheatography")

        selection.setBlock(0, in: doc.sections[2], included: true)       // re-including a block re-includes its section
        #expect(selection.state(of: doc.sections[2]) == .on)
    }
}

struct CatalogTests {
    @Test func parsesListingItemsNextPageAndTags() {
        let page = CheatographyCatalog.parseListing(Fixtures.listingPage)
        #expect(page.items.map(\.id) == ["1", "2"], "sidebar items are excluded")
        let first = page.items[0]
        #expect(first.url.absoluteString == "https://cheatography.com/sam/cheat-sheets/widget-tricks/")
        #expect(first.title == "Widget Tricks Cheat Sheet")
        #expect(first.displayTitle == "Widget Tricks")
        #expect(first.kind == "Cheat Sheet")
        #expect(first.author == "sam")
        #expect(first.summary == "About Widget Tricks Cheat Sheet & more.")
        #expect(first.thumbnailURL?.absoluteString == "https://media.cheatography.com/storage/thumb/sam_widget-tricks.400.jpg")
        #expect(first.rating == 4.5)
        #expect(first.ratingCount == 12)
        #expect(first.pageCount == 2)
        #expect(first.tags.map(\.name) == ["widgets", "tools"])
        #expect(first.tags.map(\.slug) == ["widgets", "tools"])
        #expect(first.updated == "1 Jan 19, updated 1 Jan 20")
        #expect(page.items[1].kind == "Keyboard Shortcuts")
        #expect(page.items[1].rating == nil)
        #expect(page.nextPageURL?.absoluteString == "https://cheatography.com/tag/widgets/2")
        #expect(page.heading == "2 Widget Cheat Sheets")
        #expect(page.tagGroups.first?.title == "Top Tags in Programming")
        #expect(page.tagGroups.first?.tags.map(\.slug) == ["python", "git"])
        #expect(page.tagGroups.first?.tags.first?.count == 183)
    }

    @Test func popularTagsSplitCounts() {
        let html = #"<h2>Most Popular Tags</h2><ul><li><a href="/tag/linux/">linux (240)</a></li><li><a href="/tag/python/">python</a></li></ul>"#
        let tags = CheatographyCatalog.popularTags(html)
        #expect(tags.map(\.name) == ["linux", "python"])
        #expect(tags.first?.count == 240)
    }

    @Test func searchPaginationAndSourceURLs() {
        let html = ##"<ul class="pagination"><li class="active"><a href="#">1</a></li><li><a href="/explore/search/?q=vim&amp;page=2">2</a></li></ul>"##
        #expect(CheatographyCatalog.parseListing(html).nextPageURL?.absoluteString == "https://cheatography.com/explore/search/?q=vim&page=2")
        #expect(CheatographyCatalog.Source.search("git rebase").url.absoluteString == "https://cheatography.com/explore/search/?q=git%20rebase")
        #expect(CheatographyCatalog.Source.tag(slug: "python", name: "Python").url.absoluteString == "https://cheatography.com/tag/python/cheat-sheets/")
        #expect(CheatographyCatalog.isCheatSheetURL(URL(string: "https://cheatography.com/sam/cheat-sheets/widget-tricks/")!))
        #expect(!CheatographyCatalog.isCheatSheetURL(URL(string: "https://cheatography.com/programming/")!))
    }
}

struct GenericWebImportTests {
    @Test func mainContentLayoutTablesAndChromeSuggestions() {
        let html = """
        <html><head><meta property="og:title" content="Tmux Cheatsheet"><meta property="og:site_name" content="Example Docs"></head>
        <body><div class="menu"><ul><li><a href="https://x.test/a">Home</a></li><li><a href="https://x.test/b">About</a></li></ul></div>
        <main>
          <table><tr><td><h2>Sessions</h2><table><tr><th>Key</th><th>Does</th></tr><tr><td>C-b d</td><td>Detach</td></tr></table></td>
                     <td><h2>Related posts</h2><ul><li><a href="https://x.test/c">Vim</a></li><li><a href="https://x.test/d">Git</a></li></ul></td></tr></table>
          <h2>Panes</h2>
          <ul><li><a href="https://x.test/p1">Split</a></li><li><a href="https://x.test/p2">Zoom</a></li><li><a href="https://x.test/p3">Swap</a></li></ul>
          <table><tr><th>Key</th><th>Does</th></tr><tr><td>C-b %</td><td>Split vertically</td></tr></table>
          <p>We use cookies to improve your experience.</p>
        </main></body></html>
        """
        let doc = WebExtractor.extract(text: html, url: URL(string: "https://x.test/tmux"))
        #expect(doc.extractorName == "Main content")
        #expect(doc.hasMainContent)
        #expect(doc.title == "Tmux")
        #expect(doc.siteName == "Example Docs")
        #expect(doc.sections.map(\.title) == ["Sessions", "Related posts", "Panes"])
        #expect(doc.sections[0].blocks == [.table(CheetTable(headers: ["Key", "Does"], rows: [["C-b d", "Detach"]]))])

        let suggested = doc.suggestedSelection()
        #expect(!suggested.includes(doc.sections[1].id), "“Related posts” is chrome")
        #expect(!suggested.includes(doc.sections[2].id, block: 0), "link-only list is chrome")
        #expect(suggested.includes(doc.sections[2].id, block: 1))
        #expect(!suggested.includes(doc.sections[2].id, block: 2), "cookie banner text is chrome")
        #expect(doc.cheet(selection: suggested).sections.map(\.title) == ["Sessions", "Panes"])

        let whole = WebExtractor.extract(text: html, url: nil, mainContentOnly: false)
        #expect(whole.extractorName == "Whole page")
        #expect(whole.elementCount > doc.elementCount)
    }

    @Test func markdownFromURL() {
        let doc = WebExtractor.extract(text: "# Keys\n## Move\n| k | v |\n|---|---|\n| h | left |", url: URL(string: "https://raw.example.com/keys.md"), mimeType: "text/plain")
        #expect(doc.title == "Keys")
        #expect(doc.sections.map(\.title) == ["Move"])
    }

    @Test func entityDecodingAndTitleCleaning() {
        #expect(HTMLImporter.decodeEntities("a &amp; b &#187; &#x2192; &lt;c&gt; soft&shy;hy") == "a & b » → <c> softhy")
        #expect(WebDocument.cleanTitle("Regular Expressions Cheat Sheet") == "Regular Expressions")
        #expect(WebDocument.cleanTitle("Docker - Cheatsheet") == "Docker")
        #expect(WebDocument.cleanTitle("Cheat Sheet") == "Cheat Sheet")
    }
}
