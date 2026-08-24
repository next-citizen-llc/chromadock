import AppKit
import Foundation

enum DividerManager {
    static func bundledHelperURL() -> URL? {
        Bundle.main.url(forAuxiliaryExecutable: Paths.helperExecutableName)
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/\(Paths.helperExecutableName)", isDirectory: false)
    }

    static func ensureHelpers(count: Int) throws -> [URL] {
        guard let exe = bundledHelperURL(), FileManager.default.fileExists(atPath: exe.path) else {
            throw NSError(domain: "ChromaDock", code: 2, userInfo: [NSLocalizedDescriptionKey: "Divider helper is missing from the app bundle."])
        }
        var urls: [URL] = []
        if count > 0 {
            for i in 1...count {
                urls.append(try installHelper(index: i, executable: exe))
            }
        }
        pruneHelpers(keeping: count)
        return urls
    }

    static func pruneHelpers(keeping count: Int) {
        let dir = Paths.dividersDir
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items where url.pathExtension == "app" {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("Divider ") else { continue }
            let n = Int(name.dropFirst("Divider ".count)) ?? 0
            if n < 1 || n > count {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func installHelper(index: Int, executable: URL) throws -> URL {
        let app = Paths.dividersDir.appendingPathComponent("Divider \(index).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let destExe = macos.appendingPathComponent(Paths.helperExecutableName)
        if FileManager.default.fileExists(atPath: destExe.path) {
            try FileManager.default.removeItem(at: destExe)
        }
        try FileManager.default.copyItem(at: executable, to: destExe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destExe.path)

        let ident = "\(Paths.dividerBundlePrefix)\(index)"
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "│",
            "CFBundleExecutable": Paths.helperExecutableName,
            "CFBundleIdentifier": ident,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "ChromaDock Divider \(index)",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
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
        return app
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

    static func launchHelpers(_ urls: [URL]) {
        for url in urls {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
        }
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
