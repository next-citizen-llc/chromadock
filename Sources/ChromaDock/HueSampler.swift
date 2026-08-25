import AppKit
import Foundation

enum HueSampler {
    struct Raster: Sendable {
        let size: Int
        let bytesPerRow: Int
        let bytes: [UInt8]
    }

    typealias Sample = (hue: Double, sat: Double, val: Double, colorful: Bool, hex: String, luminance: Double)

    /// AppKit icon loading and `NSImage.draw` must run on the main thread.
    @MainActor
    static func rasterize(path: String, size: Int = 48) -> Raster? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size, height: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                  from: .zero, operation: .sourceOver, fraction: 1)
        guard let ptr = rep.bitmapData else { return nil }
        let bpr = max(rep.bytesPerRow, size * 4)
        let bytes = Array(UnsafeBufferPointer(start: ptr, count: bpr * size))
        return Raster(size: size, bytesPerRow: bpr, bytes: bytes)
    }

    nonisolated static func analyze(_ raster: Raster) -> Sample? {
        let size = raster.size
        let bpr = raster.bytesPerRow
        let bytes = raster.bytes

        var hueW = [Double](repeating: 0, count: 36)
        var satW = [Double](repeating: 0, count: 36)
        var valW = [Double](repeating: 0, count: 36)
        var grayH = 0.0, grayS = 0.0, grayV = 0.0, grayN = 0.0, colorN = 0.0
        var lumSum = 0.0, lumN = 0.0

        for y in 0..<size {
            for x in 0..<size {
                let o = y * bpr + x * 4
                guard o + 3 < bytes.count else { continue }
                let a = Double(bytes[o + 3]) / 255.0
                if a < 0.4 { continue }
                let r = min(1, Double(bytes[o]) / 255.0 / max(a, 0.001))
                let g = min(1, Double(bytes[o + 1]) / 255.0 / max(a, 0.001))
                let b = min(1, Double(bytes[o + 2]) / 255.0 / max(a, 0.001))
                lumSum += LineStyle.luminance(r: r, g: g, b: b) * a
                lumN += a
                let hsvv = hsv(r: r, g: g, b: b)
                if hsvv.s < 0.12 && hsvv.v > 0.88 { continue }
                if hsvv.v < 0.08 { continue }
                let weight = a * (0.35 + hsvv.s)
                if hsvv.s < 0.18 {
                    grayH += hsvv.h * weight
                    grayS += hsvv.s * weight
                    grayV += hsvv.v * weight
                    grayN += weight
                } else {
                    let bin = min(35, Int((hsvv.h * 36.0).rounded(.down)))
                    hueW[bin] += weight
                    satW[bin] += hsvv.s * weight
                    valW[bin] += hsvv.v * weight
                    colorN += weight
                }
            }
        }

        guard lumN > 0 else { return nil }
        let luminance = lumSum / lumN

        let colorful = colorN > grayN * 0.35 && colorN > 8
        let h: Double, s: Double, v: Double
        if colorful {
            var best = 0
            for i in 1..<36 where hueW[i] > hueW[best] { best = i }
            var accH = 0.0, accW = 0.0, accS = 0.0, accV = 0.0
            for d in -2...2 {
                let i = (best + d + 36) % 36
                let wgt = hueW[i]
                accH += Double(i) * wgt
                accW += wgt
                accS += satW[i]
                accV += valW[i]
            }
            h = (accW == 0 ? Double(best) : accH / accW) / 36.0
            s = accW == 0 ? 0 : accS / accW
            v = accW == 0 ? 0 : accV / accW
        } else if grayN > 0 {
            h = grayH / grayN
            s = grayS / grayN
            v = grayV / grayN
        } else {
            h = 0
            s = 0
            v = luminance
        }
        let hue = h.truncatingRemainder(dividingBy: 1)
        return (hue, s, v, colorful, hexFromHSV(hue, s, v), luminance)
    }

    @MainActor
    static func sample(path: String, size: Int = 48) -> Sample? {
        rasterize(path: path, size: size).flatMap(analyze)
    }

    static func sortKey(_ app: DockApp) -> (Double, String) {
        (app.luminance, app.label.lowercased())
    }

    static func hueSorted(_ apps: [DockApp]) -> [DockApp] {
        apps.sorted { a, b in
            let ka = sortKey(a), kb = sortKey(b)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            return ka.1 < kb.1
        }
    }

    /// Max neighbor pull, in turns (12°). Live Dock tiles are not recolored.
    static let defaultMaxShiftTurns = 12.0 / 360.0

    struct HueNudge: Equatable, Sendable {
        var shiftedHue: Double
        var deltaTurns: Double
        var hex: String
        var applied: Bool
        var deltaDegrees: Double { deltaTurns * 360 }
        var shiftedDegrees: Double { shiftedHue * 360 }
    }

    static func wrapHue(_ h: Double) -> Double {
        var x = h.truncatingRemainder(dividingBy: 1)
        if x < 0 { x += 1 }
        return x
    }

    static func shortestHueDelta(from: Double, to: Double) -> Double {
        var d = wrapHue(to) - wrapHue(from)
        if d > 0.5 { d -= 1 }
        if d < -0.5 { d += 1 }
        return d
    }

    static func circularMeanHue(_ hues: [Double]) -> Double? {
        guard !hues.isEmpty else { return nil }
        let x = hues.reduce(0.0) { $0 + cos($1 * 2 * Double.pi) }
        let y = hues.reduce(0.0) { $0 + sin($1 * 2 * Double.pi) }
        if abs(x) < 1e-12, abs(y) < 1e-12 { return nil }
        var a = atan2(y, x) / (2 * Double.pi)
        if a < 0 { a += 1 }
        return a
    }

    /// Slight hue nudge toward immediate colorful neighbors. Gray icons stay
    /// put and do not pull. Order is unchanged. Does not rewrite Dock tiles.
    static func neighborAligned(
        _ apps: [DockApp],
        maxShiftTurns: Double = defaultMaxShiftTurns
    ) -> [HueNudge] {
        let cap = abs(maxShiftTurns)
        return apps.enumerated().map { i, app in
            guard app.colorful else {
                return HueNudge(shiftedHue: app.hue, deltaTurns: 0, hex: app.hex, applied: false)
            }
            var neighborHues: [Double] = []
            if i > 0, apps[i - 1].colorful { neighborHues.append(apps[i - 1].hue) }
            if i + 1 < apps.count, apps[i + 1].colorful { neighborHues.append(apps[i + 1].hue) }
            guard let target = circularMeanHue(neighborHues) else {
                return HueNudge(shiftedHue: app.hue, deltaTurns: 0, hex: app.hex, applied: false)
            }
            let delta = min(cap, max(-cap, shortestHueDelta(from: app.hue, to: target)))
            let shifted = wrapHue(app.hue + delta)
            return HueNudge(
                shiftedHue: shifted,
                deltaTurns: delta,
                hex: hexFromHSV(shifted, app.saturation, app.value),
                applied: abs(delta) > 1e-9
            )
        }
    }

    private static func hsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let d = mx - mn
        var h = 0.0
        if d > 1e-9 {
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        let s = mx == 0 ? 0 : d / mx
        return (h, s, mx)
    }

    private static func hexFromHSV(_ h: Double, _ s: Double, _ v: Double) -> String {
        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        let rgb: (Double, Double, Double)
        switch i % 6 {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        func ch(_ x: Double) -> Int { min(255, max(0, Int((x * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", ch(rgb.0), ch(rgb.1), ch(rgb.2))
    }
}
