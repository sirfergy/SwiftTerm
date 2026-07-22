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
    // rasterize to nil. If this precondition ever changes, the caching path in
    // MetalTerminalRenderer.glyphEntry needs revisiting — a terminal is mostly
    // blank cells, so re-rasterizing them per frame is the dominant cost this
    // guards against.
    func testRasterizerReturnsNilForZeroInkGlyphs() {
        let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
        let rasterizer = CoreTextGlyphRasterizer()
        XCTAssertNil(rasterizer.rasterize(font: font, glyph: glyph(" ", font: font)),
                     "space must have empty ink and rasterize to nil")
        XCTAssertNil(rasterizer.rasterize(font: font, glyph: glyph("\t", font: font)),
                     "tab must have empty ink and rasterize to nil")
    }

    func testRasterizerReturnsBitmapForInkedGlyphs() {
        let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
        let rasterizer = CoreTextGlyphRasterizer()
        let bitmap = rasterizer.rasterize(font: font, glyph: glyph("A", font: font))
        XCTAssertNotNil(bitmap, "an inked glyph must rasterize to a bitmap")
        if let bitmap {
            XCTAssertGreaterThan(bitmap.width, 0)
            XCTAssertGreaterThan(bitmap.height, 0)
        }
    }
}
#endif
