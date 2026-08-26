#if os(macOS) || os(iOS) || os(visionOS)
import XCTest
import CoreText
@testable import SwiftTerm

final class GlyphRasterizerTests: XCTestCase {
    private func glyph(_ scalar: Character, font: CTFont) -> CGGlyph {
        let s = String(scalar) as NSString
        var chars = [UniChar](repeating: 0, count: s.length)
        s.getCharacters(&chars)
        var glyphs = [CGGlyph](repeating: 0, count: s.length)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &chars, &glyphs, s.length))
        return glyphs[0]
    }

    // The Metal renderer's negative glyph cache exists because zero-ink glyphs
    // rasterize to `.empty`. If this precondition ever changes, the caching path
    // in MetalTerminalRenderer.glyphEntry needs revisiting — a terminal is mostly
    // blank cells, so re-rasterizing them per frame is the dominant cost this
    // guards against. Uses printable zero-ink glyphs (space, NO-BREAK SPACE) that
    // reliably map via CTFontGetGlyphsForCharacters, unlike tab.
    func testRasterizerReportsEmptyForZeroInkGlyphs() {
        let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
        let rasterizer = CoreTextGlyphRasterizer()
        for (name, ch) in [("space", Character(" ")), ("no-break space", Character("\u{00A0}"))] {
            guard case .empty = rasterizer.rasterize(font: font, glyph: glyph(ch, font: font)) else {
                XCTFail("\(name) must rasterize to .empty")
                continue
            }
        }
    }

    func testRasterizerReturnsBitmapForInkedGlyphs() {
        let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
        let rasterizer = CoreTextGlyphRasterizer()
        guard case .bitmap(let bitmap) = rasterizer.rasterize(font: font, glyph: glyph("A", font: font)) else {
            XCTFail("an inked glyph must rasterize to a bitmap")
            return
        }
        XCTAssertGreaterThan(bitmap.width, 0)
        XCTAssertGreaterThan(bitmap.height, 0)
    }
}
#endif
