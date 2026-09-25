import XCTest
@testable import CheetCore

final class TeXConverterTests: XCTestCase {
    private func tex(_ s: String) -> String { TeXConverter.convert(s) }
    private func plain(_ s: String) -> String { InlineMarkdown.plainText(TeXConverter.convert(s)) }

    func testScriptsSymbolsAndSpacing() {
        XCTAssertEqual(tex("x^2 + y^2 = z^2"), "x² + y² = z²")
        XCTAssertEqual(tex("a_{n+1} = a_n - 1"), "a^[n+1](script: -1) = a^[n](script: -1) − 1")
        XCTAssertEqual(tex(#"\alpha \leq \beta \neq \gamma"#), "α ≤ β ≠ γ")
        XCTAssertEqual(tex(#"x \in \mathbb{R}"#), "x ∈ ℝ")
        XCTAssertEqual(tex("-x"), "−x", "leading minus is unary")
        XCTAssertEqual(tex(#"e^{i\pi} + 1 = 0"#), "e^[iπ](script: 1) + 1 = 0")
        XCTAssertEqual(tex("f'(x)"), "f′(x)")
    }

    func testFractionsRootsAndStructures() {
        XCTAssertEqual(plain(#"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#), "x = (−b ± √(b² − 4ac))/2a")
        XCTAssertEqual(tex(#"\frac{1}{2}"#), "½")
        XCTAssertEqual(tex(#"\sqrt[3]{x}"#), "³√x")
        XCTAssertEqual(tex(#"\vec{v} \cdot \hat{n}"#), "v⃗ ⋅ n̂")
        XCTAssertEqual(tex(#"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#), "(a\u{2003}b; c\u{2003}d)")
        XCTAssertEqual(plain(#"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#), "∑ᵢ₌₁ⁿ\u{2009}i = n(n + 1)/2")
        XCTAssertEqual(tex(#"\sin\theta \text{ for all } \theta"#), "sin\u{2009}θ for all θ")
        XCTAssertEqual(tex(#"\left( \frac{a}{b} \right)"#), "(a/b)")
    }
}

final class MathMLTests: XCTestCase {
    func testQuadraticFormula() {
        let xml = """
        <math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow>
        <mi>x</mi><mo>=</mo><mfrac><mrow><mo>&#x2212;</mo><mi>b</mi><mo>&PlusMinus;</mo><msqrt><msup><mi>b</mi><mn>2</mn></msup><mo>&#x2212;</mo><mn>4</mn><mi>a</mi><mi>c</mi></msqrt></mrow><mrow><mn>2</mn><mi>a</mi></mrow></mfrac>
        </mrow><annotation encoding="application/x-tex">x = ...</annotation></semantics></math>
        """
        XCTAssertEqual(MathMLConverter.convert(xml).map(InlineMarkdown.plainText), "x = (−b ± √(b² − 4ac))/2a")
    }

    func testCommentsInsideTokensAreIgnored() {
        let xml = "<math><mo>&#x2212;<!-- − --></mo><mi>b</mi><mo>&#x00B1;<!-- ± --></mo><mi>c</mi></math>"
        XCTAssertEqual(MathMLConverter.convert(xml), "−b ± c")
    }

    func testScriptsAndAccents() {
        let xml = #"<math><msubsup><mo>&#x2211;</mo><mrow><mi>n</mi><mo>=</mo><mn>0</mn></mrow><mi>&#x221E;</mi></msubsup><mover><mi>x</mi><mo>&#x00AF;</mo></mover></math>"#
        XCTAssertEqual(MathMLConverter.convert(xml), "∑^[n=0](script: -1)^[∞](script: 1)\u{2009}x̄")
    }
}

final class HTMLMathAndImageTests: XCTestCase {
    func testSupSubBecomeScripts() {
        let html = "<h2>Series</h2><p>E = mc<sup>2</sup>, H<sub>2</sub>O, Σ<sup>∞</sup><sub>n=0</sub> ar<sup>n-1</sup></p>"
        let cheet = try! CheetImporter.importCheet(html, options: ImportOptions(format: .html, fallbackTitle: "T")).cheet
        guard case .text(let text) = cheet.cheets_firstBlock else { return XCTFail("expected text") }
        XCTAssertEqual(text, "E = mc², H₂O, Σ^[∞](script: 1)^[n=0](script: -1) arⁿ⁻¹")
        XCTAssertEqual(InlineMarkdown.plainText(text), "E = mc², H₂O, Σ^∞ₙ₌₀ arⁿ⁻¹")
    }

    func testCitationMarkersAreDropped() {
        let html = ##"<h2>S</h2><p>Two roots.<sup class="reference"><a href="#cite-1">[1]</a></sup> Also x<sup>2</sup>.</p>"##
        let cheet = try! CheetImporter.importCheet(html, options: ImportOptions(format: .html, fallbackTitle: "T")).cheet
        XCTAssertEqual(cheet.sections[0].blocks, [.text("Two roots. Also x².")])
    }

    func testWikipediaStyleMathUsesMathMLAndDropsFallbackImage() {
        let html = """
        <h2>Formula</h2><p>The roots are <span class="mwe-math-element"><span class="mwe-math-mathml-inline" style="display: none;">\
        <math xmlns="http://www.w3.org/1998/Math/MathML" alttext="{\\displaystyle x^{2}}"><semantics><msup><mi>x</mi><mn>2</mn></msup>\
        <annotation encoding="application/x-tex">{\\displaystyle x^{2}}</annotation></semantics></math></span>\
        <img src="https://wikimedia.org/api/rest_v1/media/math/render/svg/abc" class="mwe-math-fallback-image-inline" aria-hidden="true" alt="{\\displaystyle x^{2}}"></span> here.</p>
        """
        let cheet = try! CheetImporter.importCheet(html, options: ImportOptions(format: .html, fallbackTitle: "T")).cheet
        XCTAssertEqual(cheet.sections[0].blocks, [.text("The roots are x² here.")])
    }

    func testMathJaxScriptsRawTeXAndFormulaImages() {
        let html = """
        <html><head><script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script></head><body>
        <h2>Identities</h2>
        <p>Inline \\(a^2+b^2=c^2\\) and $\\sin^2\\theta + \\cos^2\\theta = 1$ but not $5 and $10.</p>
        <p><script type="math/tex">\\alpha \\to \\beta</script></p>
        <p>Image: <img src="https://latex.codecogs.com/png.latex?\\pi r^2" alt="\\pi r^2" class="latex"></p>
        <pre>echo $HOME \\(not math\\)</pre>
        </body></html>
        """
        let cheet = try! CheetImporter.importCheet(html, options: ImportOptions(format: .html, fallbackTitle: "T")).cheet
        let blocks = cheet.sections[0].blocks
        XCTAssertEqual(blocks[0], .text("Inline a² + b² = c² and sin²\u{2009}θ + cos²\u{2009}θ = 1 but not $5 and $10."))
        XCTAssertEqual(blocks[1], .text("α → β"))
        XCTAssertEqual(blocks[2], .text("Image: πr²"))
        XCTAssertEqual(blocks[3], .code(CodeBlock(code: "echo $HOME \\(not math\\)")))
    }

    func testImagesBlockInlineFigureLazyAndPixels() {
        let html = """
        <h2>Diagrams</h2>
        <p><img src="/img/triangle.png" alt="Right triangle"></p>
        <figure><img data-src="https://cdn.test/unit-circle.svg" src="data:image/gif;base64,R0lGOD" alt="Unit circle"><figcaption>The <b>unit</b> circle</figcaption></figure>
        <table><tr><th>Icon</th><th>Meaning</th></tr><tr><td><img src="icons/warn.png" alt="warning"></td><td>Careful</td></tr></table>
        <p>Tracked<img src="https://x.test/p.gif" width="1" height="1"></p>
        <p><img src="https://x.test/deco.png" aria-hidden="true"></p>
        """
        let cheet = try! CheetImporter.importCheet(html, options: ImportOptions(format: .html, fallbackTitle: "T", origin: "https://site.test/docs/page.html")).cheet
        let blocks = cheet.sections[0].blocks
        XCTAssertEqual(blocks[0], .image(ImageBlock(source: "https://site.test/img/triangle.png", alt: "Right triangle")))
        XCTAssertEqual(blocks[1], .image(ImageBlock(source: "https://cdn.test/unit-circle.svg", alt: "Unit circle", caption: "The **unit** circle")))
        XCTAssertEqual(blocks[2], .table(CheetTable(headers: ["Icon", "Meaning"], rows: [["![warning](https://site.test/docs/icons/warn.png)", "Careful"]])))
        XCTAssertEqual(blocks[3], .text("Tracked"))
        XCTAssertEqual(blocks.count, 4, "aria-hidden decoration is skipped")
        XCTAssertEqual(InlineMarkdown.soleImage("![warning](https://site.test/docs/icons/warn.png)")?.alt, "warning")
    }

    func testCheatographyWideTablesKeepColumnsAndBoldHeaders() {
        let html = """
        <article><section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Series</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_fivecol">
        <tr><td><div><strong>Type</strong></div></td><td><div><strong>Sum</strong></div></td><td><div><strong>Conv</strong></div></td><td><div><strong>Div</strong></div></td><td><div><strong>Notes</strong></div></td></tr>
        <tr><td><div>Infinite</div></td><td><div>Σa<sub>n</sub></div></td><td><div>Varies</div></td><td colspan="2"><div>Varies</div></td></tr>
        </table></div></section></article>
        """
        let doc = CheatographyExtractor.extract(html: html, url: nil)
        XCTAssertEqual(doc.sections[0].blocks, [.table(CheetTable(headers: ["Type", "Sum", "Conv", "Div", "Notes"], rows: [["Infinite", "Σa^[n](script: -1)", "Varies", "Varies", ""]]))])
    }

    func testImageMarkdownRoundTripAndJSON() throws {
        let cheet = Cheet(title: "T", sections: [CheetSection(title: "S", blocks: [.image(ImageBlock(source: "https://x.test/a b.png", alt: "A [b]", caption: "Cap"))])])
        let markdown = MarkdownExporter.markdown(for: cheet)
        XCTAssertTrue(markdown.contains(#"![A \[b\]](https://x.test/a%20b.png "Cap")"#), markdown)
        let back = try CheetImporter.importCheet(markdown).cheet
        XCTAssertEqual(back.sections[0].blocks, [.image(ImageBlock(source: "https://x.test/a%20b.png", alt: "A [b]", caption: "Cap"))])
        let json = try JSONEncoder.cheet.encode(cheet)
        XCTAssertEqual(try JSONDecoder.cheet.decode(Cheet.self, from: json).sections, cheet.sections)
    }

    func testCheatographyImageBlocksAndScripts() {
        let html = """
        <article><section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Roots</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_image"><tr><td class="cheat_sheet_output_cell_1">
        <a class="thumb imagelink" href="//media.cheatography.com/uploads/sq.jpeg"><img width="270" src="//media.cheatography.com/uploads/sq.jpeg"></a></td></tr></table></div></section>
        <section class="cheat_sheet_output_wrapper"><h3 class="cheat_sheet_output_title">Series</h3>
        <div class="cheat_sheet_output_block"><table class="cheat_sheet_output_twocol"><tr><td class="cheat_sheet_output_cell_1"><div>Geometric</div></td>
        <td class="cheat_sheet_output_cell_2"><div>Σ<sup>∞</sup><sub>n=0</sub> ar<sup>n</sup></div></td></tr></table></div></section></article>
        """
        let doc = CheatographyExtractor.extract(html: html, url: URL(string: "https://cheatography.com/x/cheat-sheets/y/"))
        XCTAssertEqual(doc.sections[0].blocks, [.image(ImageBlock(source: "https://media.cheatography.com/uploads/sq.jpeg"))])
        XCTAssertEqual(doc.sections[1].blocks, [.table(CheetTable(rows: [["Geometric", "Σ^[∞](script: 1)^[n=0](script: -1) arⁿ"]]))])
        XCTAssertEqual(WebDocument.summary(of: doc.sections[0].blocks[0]).kind, .image)
    }
}

private extension Cheet {
    var cheets_firstBlock: CheetBlock? { sections.first?.blocks.first }
}
