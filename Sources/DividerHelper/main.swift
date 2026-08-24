import AppKit

/// Transparent Dock tile: draws only a vertical chrome line so the Dock glass
/// shows through. Must run as a regular app (not LSUIElement) for the Dock
/// to bind `NSDockTile.contentView` to the kept-in-Dock icon.
final class LineView: NSView {
    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        let w = max(2.0, min(4.0, bounds.width * 0.045))
        let x = (bounds.width - w) / 2
        let inset = bounds.height * 0.05
        let rect = NSRect(x: x, y: inset, width: w, height: bounds.height - inset * 2)
        NSColor(calibratedWhite: 1, alpha: 0.90).setFill()
        NSBezierPath(roundedRect: rect, xRadius: w / 2, yRadius: w / 2).fill()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let view = LineView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
app.dockTile.contentView = view
app.dockTile.display()
app.run()
