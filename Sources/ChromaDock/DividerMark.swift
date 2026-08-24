import CoreGraphics
import Foundation

enum DividerStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case line
    case dash

    var id: String { rawValue }

    /// Shipped marks. Extra cases can join this list later.
    static let catalog: [DividerStyle] = [.line, .dash]

    static let dashCount = 4

    var letter: String {
        switch self {
        case .line: return "A"
        case .dash: return "B"
        }
    }

    var accessibilityName: String {
        switch self {
        case .line: return "Separator A, solid line"
        case .dash: return "Separator B, dashed line"
        }
    }

    static func fromStored(_ raw: String?) -> DividerStyle {
        switch raw {
        case "dash", "dots": return .dash
        default: return .line
        }
    }
}

enum DividerMark {
    static func draw(ctx: CGContext, bounds: CGRect, style: DividerStyle, paint: LineStyle.Paint) {
        ctx.setFillColor(CGColor(gray: paint.white, alpha: paint.alpha))
        switch style {
        case .line:
            let w = max(1.0, min(1.5, (bounds.width * 0.012).rounded()))
            let x = ((bounds.width - w) / 2).rounded(.down)
            let inset = max(2.0, bounds.height * 0.10)
            ctx.fill(CGRect(x: x, y: inset, width: w, height: bounds.height - inset * 2))
        case .dash:
            for rect in dashRects(in: bounds) {
                ctx.fill(rect)
            }
        }
    }

    static func dashRects(in bounds: CGRect) -> [CGRect] {
        let w = max(1.0, min(1.5, (bounds.width * 0.012).rounded()))
        let x = ((bounds.width - w) / 2).rounded(.down)
        let inset = max(2.0, bounds.height * 0.12)
        let usable = max(bounds.height - inset * 2, 8)
        let gaps = CGFloat(DividerStyle.dashCount - 1)
        let gap = usable / (CGFloat(DividerStyle.dashCount) * 2 + gaps)
        let dash = gap * 2
        var y = inset
        var rects: [CGRect] = []
        for _ in 0..<DividerStyle.dashCount {
            rects.append(CGRect(x: x, y: y, width: w, height: dash))
            y += dash + gap
        }
        return rects
    }
}
