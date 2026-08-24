import CoreGraphics
import Foundation

enum LineStyle {
    struct Paint: Equatable {
        var white: Double
        var alpha: Double

        static let light = Paint(white: 1.0, alpha: 0.42)
        static let dark = Paint(white: 0.05, alpha: 0.55)
    }

    /// Rec. 709 luminance in 0...1.
    static func luminance(r: Double, g: Double, b: Double) -> Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Dark wallpaper (or night-mode dark region) gets a dark hairline;
    /// light regions get a light hairline. The previous mapping was inverted.
    static func paint(luminance: Double, darkAppearance: Bool) -> Paint {
        let threshold = darkAppearance ? 0.50 : 0.42
        return luminance < threshold ? .dark : .light
    }

    static func tileCenterX(
        visualIndex: Int,
        tileCount: Int,
        tileSize: Double,
        spacing: Double,
        screenWidth: Double
    ) -> Double {
        let n = max(tileCount, 1)
        let total = Double(n) * tileSize + Double(max(n - 1, 0)) * spacing
        let start = (screenWidth - total) / 2
        return start + Double(visualIndex) * (tileSize + spacing) + tileSize / 2
    }
}
