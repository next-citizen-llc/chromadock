import CoreGraphics
import Foundation

enum DividerStyle: String, Codable, CaseIterable, Sendable {
    case line
    case dots
}

enum DividerMark {
    static func draw(ctx: CGContext, bounds: CGRect, style: DividerStyle, paint: LineStyle.Paint) {
        let alpha = style == .dots ? max(paint.alpha, 0.90) : paint.alpha
        ctx.setFillColor(CGColor(gray: paint.white, alpha: alpha))
        switch style {
        case .line:
            let w = max(1.0, min(1.5, (bounds.width * 0.012).rounded()))
            let x = ((bounds.width - w) / 2).rounded(.down)
            let inset = max(2.0, bounds.height * 0.10)
            ctx.fill(CGRect(x: x, y: inset, width: w, height: bounds.height - inset * 2))
        case .dots:
            let s = min(bounds.width, bounds.height)
            let cx = bounds.midX
            let cy = bounds.midY
            let rMain = max(3.0, s * 0.14)
            let rSide = max(1.6, rMain * 0.42)
            let spread = rMain + rSide + max(2.0, s * 0.06)
            fillCircle(ctx, CGPoint(x: cx - spread, y: cy), rSide)
            fillCircle(ctx, CGPoint(x: cx, y: cy), rMain)
            fillCircle(ctx, CGPoint(x: cx + spread, y: cy), rSide)
        }
    }

    static func circleLayout(in bounds: CGRect) -> (main: CGRect, left: CGRect, right: CGRect) {
        let s = min(bounds.width, bounds.height)
        let cx = bounds.midX
        let cy = bounds.midY
        let rMain = max(3.0, s * 0.14)
        let rSide = max(1.6, rMain * 0.42)
        let spread = rMain + rSide + max(2.0, s * 0.06)
        func box(_ c: CGPoint, _ r: CGFloat) -> CGRect {
            CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        }
        return (
            box(CGPoint(x: cx, y: cy), rMain),
            box(CGPoint(x: cx - spread, y: cy), rSide),
            box(CGPoint(x: cx + spread, y: cy), rSide)
        )
    }

    private static func fillCircle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}
