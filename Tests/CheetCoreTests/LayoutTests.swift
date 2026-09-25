import Foundation
import Testing
@testable import CheetCore

struct CardPackerTests {
    @Test func equalWidthsBehaveLikeMasonryColumns() {
        // 3 columns of 100 with 10pt gaps in a 320pt container.
        let sizes = [CGSize(width: 100, height: 50), CGSize(width: 100, height: 80), CGSize(width: 100, height: 30),
                     CGSize(width: 100, height: 40)]
        let (frames, height) = CardPacker.pack(sizes: sizes, containerWidth: 320, spacing: 10)
        #expect(frames[0].origin == CGPoint(x: 0, y: 0))
        #expect(frames[1].origin == CGPoint(x: 110, y: 0))
        #expect(frames[2].origin == CGPoint(x: 220, y: 0))
        // Fourth card drops into the shortest column (the third, height 30).
        #expect(frames[3].origin == CGPoint(x: 220, y: 40))
        #expect(height == 80)
    }

    @Test func wideCardSitsBelowTheTallestColumnItSpans() {
        let sizes = [CGSize(width: 100, height: 50), CGSize(width: 100, height: 120), CGSize(width: 100, height: 30),
                     CGSize(width: 210, height: 40)]
        let (frames, _) = CardPacker.pack(sizes: sizes, containerWidth: 320, spacing: 10)
        // Every two-column position overlaps the 120pt column, so the wide card starts below it.
        #expect(frames[3].minY == 130)
        #expect(frames[3].width == 210)
    }

    @Test func cardsFlowIntoGapsBesideAWideCard() {
        let sizes = [CGSize(width: 210, height: 100), CGSize(width: 100, height: 40), CGSize(width: 100, height: 40)]
        let (frames, height) = CardPacker.pack(sizes: sizes, containerWidth: 320, spacing: 10)
        #expect(frames[1].origin == CGPoint(x: 220, y: 0))
        #expect(frames[2].origin == CGPoint(x: 220, y: 50))
        #expect(height == 100)
    }

    @Test func randomLayoutsNeverOverlapOrOverflow() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let width = CGFloat.random(in: 300...1400, using: &generator)
            let sizes = (0..<Int.random(in: 1...18, using: &generator)).map { _ in
                CGSize(width: CGFloat.random(in: 60...width * 1.2, using: &generator), height: CGFloat.random(in: 20...400, using: &generator))
            }
            let (frames, height) = CardPacker.pack(sizes: sizes, containerWidth: width, spacing: 12)
            for (i, a) in frames.enumerated() {
                #expect(a.minX >= -0.01)
                #expect(a.maxX <= width + 0.51)
                #expect(a.maxY <= height + 0.01)
                for b in frames[(i + 1)...] {
                    #expect(!a.insetBy(dx: 1, dy: 1).intersects(b.insetBy(dx: 1, dy: 1)), "\(a) overlaps \(b)")
                }
            }
        }
    }
}

struct SectionLayoutTests {
    @Test func layoutRoundTripsAndDefaultIsOmitted() throws {
        var section = CheetSection(title: "S", blocks: [.text("x")])
        let plain = try JSONEncoder.cheet.encode(section)
        #expect(!String(decoding: plain, as: UTF8.self).contains("layout"))

        section.layout.isHidden = true
        section.layout.width = .columns(2)
        section.layout.height = 240
        section.layout.style.fontSize = 17
        section.layout.style.fill = .gradient
        section.layout.style.effect = .glow
        section.layout.style.titleColor = RGBAColor(r: 1, g: 0.5, b: 0)
        let data = try JSONEncoder.cheet.encode(section)
        #expect(try JSONDecoder.cheet.decode(CheetSection.self, from: data) == section)

        var fraction = SectionLayout()
        fraction.width = .fraction(0.42)
        #expect(try JSONDecoder.cheet.decode(SectionLayout.self, from: JSONEncoder.cheet.encode(fraction)) == fraction)
    }

    @Test func partialLayoutJSONUsesDefaults() throws {
        let json = #"{"title":"T","blocks":[],"layout":{"width":{"columns":3},"style":{"fill":"solid","bogus":1}}}"#
        let section = try JSONDecoder.cheet.decode(CheetSection.self, from: Data(json.utf8))
        #expect(section.layout.width == .columns(3))
        #expect(section.layout.style.fill == .solid)
        #expect(section.layout.style.fillOpacity == CardStyle().fillOpacity)
        #expect(!section.layout.isHidden)
    }

    @Test func replacingContentKeepsLayoutByTitle() throws {
        var cheet = try CheetImporter.importCheet("# T\n## A\n- a\n## B\n- b\n## C\n- c").cheet
        cheet.sections[1].layout.width = .columns(2)
        cheet.sections[2].layout.isHidden = true
        let idB = cheet.sections[1].id

        let edited = try CheetImporter.importCheet("# T2\n## B\n- b changed\n## New\n- n\n## C\n- c").cheet
        cheet.replaceContent(with: edited)
        #expect(cheet.title == "T2")
        #expect(cheet.sections.map(\.title) == ["B", "New", "C"])
        #expect(cheet.sections[0].id == idB)
        #expect(cheet.sections[0].layout.width == .columns(2))
        #expect(cheet.sections[1].layout.isDefault)
        #expect(cheet.sections[2].layout.isHidden)
        #expect(cheet.visibleSections.map(\.title) == ["B", "New"])
        #expect(cheet.hiddenSectionCount == 1)
    }
}

struct LayoutSearchTests {
    @Test func filteringKeepsCardStyleButReleasesFixedHeight() throws {
        var cheet = try CheetImporter.importCheet("# T\n## Keys\n| k | v |\n|---|---|\n| a | apple |\n| b | banana |").cheet
        cheet.sections[0].layout.width = .columns(2)
        cheet.sections[0].layout.height = 90
        cheet.sections[0].layout.style.fill = .solid
        let result = CheetSearchIndex(cheet: cheet).filter("banana")
        #expect(result.count == 1)
        #expect(result[0].layout.width == .columns(2))
        #expect(result[0].layout.style.fill == .solid)
        #expect(result[0].layout.height == nil)
    }
}
