import AppKit

/// Transparent Dock tile: a Trash-style chrome hairline. Bind `contentView`
/// while regular, then switch to accessory so the running-app dot is not shown.
final class LineView: NSView {
    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        let w = max(1.0, min(1.5, (bounds.width * 0.012).rounded()))
        let x = ((bounds.width - w) / 2).rounded(.down)
        let inset = max(2.0, bounds.height * 0.10)
        NSColor(calibratedWhite: 1.0, alpha: 0.42).setFill()
        NSRect(x: x, y: inset, width: w, height: bounds.height - inset * 2).fill()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let line = LineView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement helpers stay file-tiles. Do not flip through `.regular`:
        // that enrolls a running-app Dock tile and then `.accessory` discards
        // the bound contentView, leaving the bundle icon (or a glass plate).
        bindTile()
    }

    func bindTile() {
        NSApp.dockTile.contentView = line
        NSApp.dockTile.display()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
