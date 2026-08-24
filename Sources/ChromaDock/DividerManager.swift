import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DividerManager {
    static func bundledHelperURL() -> URL? {
        Bundle.main.url(forAuxiliaryExecutable: Paths.helperExecutableName)
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/\(Paths.helperExecutableName)", isDirectory: false)
    }

    static func ensureHelpers(count: Int, style: DividerStyle = .line) throws -> [URL] {
        guard let exe = bundledHelperURL(), FileManager.default.fileExists(atPath: exe.path) else {
            throw NSError(domain: "ChromaDock", code: 2, userInfo: [NSLocalizedDescriptionKey: "Divider helper is missing from the app bundle."])
        }
        var urls: [URL] = []
        if count > 0 {
            let icon = FileManager.default.temporaryDirectory.appendingPathComponent("chromadock-divider-\(UUID().uuidString).icns")
            defer { try? FileManager.default.removeItem(at: icon) }
            try writeMarkIcns(to: icon, style: style)
            for i in 1...count {
                urls.append(try installHelper(index: i, executable: exe, icon: icon))
            }
        }
        pruneHelpers(keeping: count)
        try? FileManager.default.removeItem(at: Paths.legacyDividersDir)
        return urls
    }

    static func rewriteInstalledIcons(style: DividerStyle) throws {
        let icon = FileManager.default.temporaryDirectory.appendingPathComponent("chromadock-mark-\(UUID().uuidString).icns")
        defer { try? FileManager.default.removeItem(at: icon) }
        try writeMarkIcns(to: icon, style: style)
        for url in installedHelperURLs() {
            let dest = url.appendingPathComponent("Contents/Resources/Line.icns")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: icon, to: dest)
            _ = try? DockIO.run(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                ["-f", url.path]
            )
        }
    }

    static func helperAppName(index: Int) -> String { "Line \(index).app" }

    static func helperIndex(fromAppName name: String) -> Int? {
        for prefix in ["Line ", "Divider "] {
            if name.hasPrefix(prefix), let n = Int(name.dropFirst(prefix.count)), n > 0 {
                return n
            }
        }
        return nil
    }

    static func pruneHelpers(keeping count: Int) {
        let dir = Paths.dividersDir
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items where url.pathExtension == "app" {
            let name = url.deletingPathExtension().lastPathComponent
            let n = helperIndex(fromAppName: name) ?? 0
            if n < 1 || n > count {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func installHelper(
        index: Int,
        executable: URL,
        into dir: URL = Paths.dividersDir,
        icon: URL? = nil
    ) throws -> URL {
        let app = dir.appendingPathComponent(helperAppName(index: index), isDirectory: true)
        let contents = app.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: resources.path) {
            try FileManager.default.removeItem(at: resources)
        }
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let destExe = macos.appendingPathComponent(Paths.helperExecutableName)
        if FileManager.default.fileExists(atPath: destExe.path) {
            try FileManager.default.removeItem(at: destExe)
        }
        try FileManager.default.copyItem(at: executable, to: destExe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destExe.path)

        let iconURL = resources.appendingPathComponent("Line.icns")
        if let icon {
            try FileManager.default.copyItem(at: icon, to: iconURL)
        } else {
            try writeMarkIcns(to: iconURL, style: .line)
        }

        let ident = "\(Paths.dividerBundlePrefix)\(index)"
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "│",
            "CFBundleExecutable": Paths.helperExecutableName,
            "CFBundleIconFile": "Line",
            "CFBundleIdentifier": ident,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "ChromaDock Divider \(index)",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.4",
            "CFBundleVersion": "5",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true
        ]
        let infoURL = contents.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL)
        try "APPL????".write(to: contents.appendingPathComponent("PkgInfo"), atomically: true, encoding: .utf8)

        _ = try? DockIO.run("/usr/bin/codesign", [
            "--force", "--sign", "-", "--identifier", ident, app.path
        ])
        _ = try? DockIO.run("/usr/bin/xattr", ["-cr", app.path])
        _ = try? DockIO.run(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", app.path]
        )
        return app
    }

    static func hairlinePNG(pixelSize: Int) throws -> Data {
        try markPNG(pixelSize: pixelSize, style: .line, paint: .light)
    }

    static func markPNG(
        pixelSize: Int,
        style: DividerStyle,
        paint: LineStyle.Paint = .dark
    ) throws -> Data {
        guard pixelSize > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw NSError(domain: "ChromaDock", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not draw divider icon."])
        }
        ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        let resolved = style == .dots ? LineStyle.Paint(white: 0.0, alpha: 1.0) : paint
        DividerMark.draw(
            ctx: ctx,
            bounds: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            style: style,
            paint: resolved
        )
        guard let image = ctx.makeImage() else {
            throw NSError(domain: "ChromaDock", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not draw divider icon."])
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "ChromaDock", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode divider icon."])
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "ChromaDock", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode divider icon."])
        }
        return data as Data
    }

    static func writeHairlineIcns(to dest: URL) throws {
        try writeMarkIcns(to: dest, style: .line)
    }

    static func writeMarkIcns(to dest: URL, style: DividerStyle) throws {
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("chromadock-line-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }
        let entries: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for (name, size) in entries {
            try markPNG(pixelSize: size, style: style).write(to: iconset.appendingPathComponent(name))
        }
        _ = try DockIO.run("/usr/bin/iconutil", ["-c", "icns", "-o", dest.path, iconset.path])
    }

    static func dividerTile(index: Int, appURL: URL) -> [String: Any] {
        var urlString = appURL.absoluteString
        if !urlString.hasSuffix("/") { urlString += "/" }
        var td: [String: Any] = [
            "bundle-identifier": "\(Paths.dividerBundlePrefix)\(index)",
            "dock-extra": false,
            "file-label": "│",
            "file-type": 41,
            "is-beta": false,
            "file-data": [
                "_CFURLString": urlString,
                "_CFURLStringType": 15
            ]
        ]
        if let book = DockIO.makeBookmark(path: appURL.path) {
            td["book"] = book
        }
        return [
            "GUID": UInt32.random(in: 1...UInt32.max),
            "tile-type": "file-tile",
            "tile-data": td
        ]
    }

    static func installedHelperURLs(in dir: URL = Paths.dividersDir) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return items
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func dividerIndex(fromBundleID id: String) -> Int? {
        for prefix in Paths.allDividerBundlePrefixes {
            if id.hasPrefix(prefix), let n = Int(id.dropFirst(prefix.count)), n > 0 {
                return n
            }
        }
        return nil
    }

    static func dividerCount(in tiles: [[String: Any]]) -> Int {
        tiles.compactMap { tile -> Int? in
            guard DockIO.isDividerTile(tile), let id = DockIO.bundleID(of: tile) else { return nil }
            return dividerIndex(fromBundleID: id)
        }.max() ?? 0
    }

    static func bundleID(forHelperApp url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let n = helperIndex(fromAppName: name) else { return nil }
        return "\(Paths.dividerBundlePrefix)\(n)"
    }

    static func runningHelperCount(for urls: [URL]) -> Int {
        urls.reduce(into: 0) { count, url in
            guard let id = bundleID(forHelperApp: url) else { return }
            if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                count += 1
            }
        }
    }

    @MainActor
    static func launchHelpers(_ urls: [URL], retries: Int = 2) async -> Int {
        guard !urls.isEmpty else { return 0 }
        var pending = urls
        for attempt in 0...max(retries, 0) {
            if pending.isEmpty { break }
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            for url in pending {
                await openHelper(url)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            pending = pending.filter { url in
                guard let id = bundleID(forHelperApp: url) else { return true }
                return NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            }
        }
        return urls.count - pending.count
    }

    @MainActor
    private static func openHelper(_ url: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
                cont.resume()
            }
        }
    }

    static let linesLaunchAgentLabel = "llc.nextcitizen.ChromaDock.lines"

    static func linesLaunchAgentPlist(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(linesLaunchAgentLabel).plist")
    }

    static func linesKeepScript(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/ChromaDock/keep-lines.sh")
    }

    static func installLinesLaunchAgent() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let script = linesKeepScript(home: home)
        let plist = linesLaunchAgentPlist(home: home)
        let dir = Paths.dividersDir.path
        let body = """
        #!/bin/bash
        DIR=\(shellSingleQuote(dir))
        while true; do
          if [[ -d "$DIR" ]]; then
            shopt -s nullglob
            for app in "$DIR"/Line\\ *.app; do
              exe="$app/Contents/MacOS/\(Paths.helperExecutableName)"
              if [[ -x "$exe" ]] && ! pgrep -f "$exe" >/dev/null 2>&1; then
                /usr/bin/open -g "$app" || true
              fi
            done
          fi
          sleep 2
        done
        """
        do {
            try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let agent: [String: Any] = [
                "Label": linesLaunchAgentLabel,
                "RunAtLoad": true,
                "KeepAlive": true,
                "ProgramArguments": ["/bin/bash", script.path]
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plist)
            let uid = getuid()
            _ = try? DockIO.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(linesLaunchAgentLabel)"])
            _ = try? DockIO.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist.path])
        } catch {
            return
        }
    }

    static func unloadLinesLaunchAgent() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plist = linesLaunchAgentPlist(home: home)
        let uid = getuid()
        _ = try? DockIO.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(linesLaunchAgentLabel)"])
        if FileManager.default.fileExists(atPath: plist.path) {
            _ = try? DockIO.run("/bin/launchctl", ["unload", plist.path])
            try? FileManager.default.removeItem(at: plist)
        }
        try? FileManager.default.removeItem(at: linesKeepScript(home: home))
        _ = try? DockIO.run("/usr/bin/pkill", ["-f", "Application Support/ChromaDock/keep-lines.sh"])
    }

    private static func shellSingleQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static let legacyLaunchAgentLabel = "com.nextcz.dock-dividers"

    static func legacyLaunchAgentPlist(home: URL) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(legacyLaunchAgentLabel).plist")
    }

    static func legacyStartScript(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/dock-group-hue/start-dividers.sh")
    }

    static func legacyApplicationsDir(home: URL) -> URL {
        home.appendingPathComponent("Applications/Dock Dividers", isDirectory: true)
    }

    static func legacySupportDir(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/dock-group-hue", isDirectory: true)
    }

    static func stopHelpers() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        unloadLinesLaunchAgent()
        unloadLegacyLaunchAgent(home: home)
        _ = try? DockIO.run("/usr/bin/pkill", ["-f", "dock-group-hue/start-dividers.sh"])
        _ = try? DockIO.run("/usr/bin/pkill", ["-x", Paths.helperExecutableName])
        _ = try? DockIO.run("/usr/bin/pkill", ["-f", "Dock Dividers/Divider .*\\.app/Contents/MacOS/divider"])
        _ = try? DockIO.run("/usr/bin/pkill", ["-f", "dock-group-hue/dividers/Divider .*\\.app/Contents/MacOS/divider"])
        removeLegacyInstalls(home: home)
    }

    static func unloadLegacyLaunchAgent(home: URL) {
        let plist = legacyLaunchAgentPlist(home: home)
        let uid = getuid()
        _ = try? DockIO.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(legacyLaunchAgentLabel)"])
        if FileManager.default.fileExists(atPath: plist.path) {
            _ = try? DockIO.run("/bin/launchctl", ["unload", plist.path])
            try? FileManager.default.removeItem(at: plist)
        }
    }

    static func removeLegacyInstalls(home: URL) {
        try? FileManager.default.removeItem(at: legacyApplicationsDir(home: home))
        try? FileManager.default.removeItem(at: legacySupportDir(home: home))
    }
}
