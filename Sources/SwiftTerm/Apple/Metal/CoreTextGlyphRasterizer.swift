#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics
import CoreText

/// Outcome of a glyph rasterization attempt.
///
/// `empty` and `failed` are deliberately distinct: `empty` is a deterministic
/// property of the glyph (zero ink — space, tab, …) and is safe to memoize,
/// whereas `failed` is a transient error (e.g. a `CGContext` allocation failure
/// under memory pressure) for an otherwise-inked glyph and must NOT be cached, or
/// a momentary failure would permanently blank a valid glyph.
enum GlyphRasterization {
    case bitmap(GlyphBitmap)
    case empty
    case failed
}

final class CoreTextGlyphRasterizer {
    var fontSmoothing: Bool = true

    func rasterize(font: CTFont, glyph: CGGlyph) -> GlyphRasterization {
        var glyphVar = glyph
        let rect = CTFontGetBoundingRectsForGlyphs(font, .default, &glyphVar, nil, 1)
        if rect.width <= 0 || rect.height <= 0 {
            return .empty
        }

        let minX = floor(rect.origin.x)
        let minY = floor(rect.origin.y)
        let maxX = ceil(rect.origin.x + rect.size.width)
        let maxY = ceil(rect.origin.y + rect.size.height)
        let width = Int(maxX - minX)
        let height = Int(maxY - minY)
        if width <= 0 || height <= 0 {
            return .empty
        }

        let bytesPerPixel = 4
        var pixels = Array(repeating: UInt8(0), count: width * height * bytesPerPixel)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else {
                return false
            }
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                return false
            }
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            guard let context = CGContext(data: base,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * bytesPerPixel,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return false
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSubpixelPositioning(true)
            context.setShouldSubpixelPositionFonts(true)
            context.setAllowsFontSubpixelQuantization(false)
            context.setShouldSubpixelQuantizeFonts(false)
#if os(macOS)
            context.setAllowsFontSmoothing(fontSmoothing)
            context.setShouldSmoothFonts(fontSmoothing)
#else
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)
#endif

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

            var positions = [CGPoint(x: -minX, y: -minY)]
            CTFontDrawGlyphs(font, &glyphVar, &positions, 1, context)
            return true
        }
        if !drew {
            return .failed
        }

        var isColor = false
        var idx = 0
        while idx < pixels.count {
            let b = pixels[idx]
            let g = pixels[idx + 1]
            let r = pixels[idx + 2]
            if r != g || g != b {
                isColor = true
                break
            }
            idx += 4
        }

        return .bitmap(GlyphBitmap(width: width,
                                   height: height,
                                   bearing: CGPoint(x: minX, y: minY),
                                   pixels: pixels,
                                   isColor: isColor))
    }
}
#endif
