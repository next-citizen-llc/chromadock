import AppKit
import Foundation

enum DividerManager {
    static func bundledHelperURL() -> URL? {
        Bundle.main.url(forAuxiliaryExecutable: Paths.helperExecutableName)
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/\(Paths.helperExecutableName)", isDirectory: false)
    }

    static func ensureHelpers(count: Int) throws -> [URL] {
        guard count > 0 else { return [] }
        guard let exe = bundledHelperURL(), FileManager.default.fileExists(atPath: exe.path) else {
            throw NSError(domain: "ChromaDock", code: 2, userInfo: [NSLocalizedDescriptionKey: "Divider helper is missing from the app bundle."])
        }
        var urls: [URL] = []
        for i in 1...count {
            urls.append(try installHelper(index: i, executable: exe))
        }
        return urls
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

        if let icns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            let destIcns = resources.appendingPathComponent("AppIcon.icns")
            if FileManager.default.fileExists(atPath: destIcns.path) {
                try FileManager.default.removeItem(at: destIcns)
            }
            try FileManager.default.copyItem(at: icns, to: destIcns)
        }

        let ident = "\(Paths.dividerBundlePrefix)\(index)"
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "│",
            "CFBundleExecutable": Paths.helperExecutableName,
            "CFBundleIconFile": "AppIcon",
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

    static func stopHelpers() {
        _ = try? DockIO.run("/usr/bin/pkill", ["-x", Paths.helperExecutableName])
    }
}
