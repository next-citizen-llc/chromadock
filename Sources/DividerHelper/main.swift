import AppKit
import CoreGraphics
import Foundation

/// Transparent Dock tile: a hairline over Dock glass. Helpers stay `.regular`
/// so `NSDockTile.contentView` sticks and the running-app dot is shown.
final class LineView: NSView {
    var paint = LineStyle.Paint.light
    var style = DividerStyle.line

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        DividerMark.draw(ctx: ctx, bounds: bounds, style: style, paint: paint)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let line = LineView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
    private var daily: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bindTile()
        refreshStyle()
        observeAppearance()
        daily = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            self?.refreshStyle()
        }
        daily?.tolerance = 3_600
    }

    func bindTile() {
        NSApp.dockTile.contentView = line
        NSApp.dockTile.display()
    }

    func refreshStyle() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let nextPaint: LineStyle.Paint
        if let y = sampleWallpaperLuminance() {
            nextPaint = LineStyle.paint(luminance: y, darkAppearance: dark)
        } else {
            nextPaint = dark ? .light : .dark
        }
        let nextStyle = currentDividerStyle()
        if nextPaint != line.paint || nextStyle != line.style {
            line.paint = nextPaint
            line.style = nextStyle
            line.needsDisplay = true
            bindTile()
        }
    }

    private func currentDividerStyle() -> DividerStyle {
        guard let data = try? Data(contentsOf: Paths.settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .line
        }
        return settings.dividerStyle
    }

    private func observeAppearance() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSApp.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new], context: nil)
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name(Paths.settingsChangedNotification),
            object: nil
        )
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "effectiveAppearance" {
            appearanceChanged()
        }
    }

    @objc private func appearanceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshStyle()
        }
    }

    private func sampleWallpaperLuminance() -> Double? {
        guard let screen = dockScreen() else { return nil }
        guard let cg = desktopImage(for: screen) else { return nil }
        let local = sampleRect(on: screen)
        return WallpaperSampler.meanLuminance(
            of: cg,
            screenSize: screen.frame.size,
            sampleInScreen: local
        )
    }

    private func desktopImage(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let ns = NSImage(contentsOf: url) else { return nil }
        var rect = NSRect(origin: .zero, size: ns.size)
        var image: CGImage?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            image = ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return image
    }

    private func dockScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private func sampleRect(on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let tileSize = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 48
        let spacing = max(4.0, tileSize * 0.12)
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        let layout = dockLayout()
        let alongAxis = (orientation == "left" || orientation == "right") ? frame.height : frame.width
        let along = LineStyle.tileCenterX(
            visualIndex: layout.visualIndex,
            tileCount: layout.tileCount,
            tileSize: tileSize,
            spacing: spacing,
            screenWidth: alongAxis
        )
        let half = max(tileSize / 3, 8)
        switch orientation {
        case "left":
            let dockW = max(visible.minX - frame.minX, 40)
            return CGRect(x: 0, y: along - half, width: dockW, height: half * 2)
        case "right":
            let dockW = max(frame.maxX - visible.maxX, 40)
            return CGRect(x: frame.width - dockW, y: along - half, width: dockW, height: half * 2)
        default:
            let dockH = max(visible.minY - frame.minY, 40)
            return CGRect(x: along - half, y: 0, width: half * 2, height: dockH)
        }
    }

    private func dockLayout() -> (visualIndex: Int, tileCount: Int) {
        let id = Bundle.main.bundleIdentifier ?? ""
        var apps: [[String: Any]] = []
        var others: [[String: Any]] = []
        if let dict = dockPlist() {
            apps = dict["persistent-apps"] as? [[String: Any]] ?? []
            others = dict["persistent-others"] as? [[String: Any]] ?? []
        }
        let plistIndex = apps.firstIndex { tile in
            let td = tile["tile-data"] as? [String: Any] ?? [:]
            return (td["bundle-identifier"] as? String) == id
        } ?? 0
        // Finder is pinned left of persistent-apps and is not in the array.
        let visualIndex = 1 + plistIndex
        let tileCount = 1 + apps.count + others.count
        return (visualIndex, max(tileCount, visualIndex + 1))
    }

    private func dockPlist() -> [String: Any]? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("chroma-line-dock-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["export", "com.apple.dock", tmp.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = try Data(contentsOf: tmp)
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        } catch {
            return nil
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
