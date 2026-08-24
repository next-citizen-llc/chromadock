import Foundation

enum Paths {
    static let appSupportName = "ChromaDock"
    /// Current helper bundle-id prefix. Bumped off `.divider.` so Dock
    /// cannot keep serving the leftover ChromaDock `AppIcon.icns` cache.
    static let dividerBundlePrefix = "llc.nextcitizen.ChromaDock.line."
    static let legacyDividerBundlePrefixes = [
        "llc.nextcitizen.ChromaDock.divider.",
        "com.nextcz.dockdivider."
    ]
    static var allDividerBundlePrefixes: [String] {
        [dividerBundlePrefix] + legacyDividerBundlePrefixes
    }
    static let helperExecutableName = "ChromaDockDivider"

    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent(appSupportName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var settingsURL: URL { appSupport.appendingPathComponent("settings.json") }
    static var backupsDir: URL {
        let url = appSupport.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var dividersDir: URL {
        let url = appSupport.appendingPathComponent("Dividers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var latestBackup: URL { backupsDir.appendingPathComponent("com.apple.dock.latest.plist") }
    static var dockPlist: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
    }
}
