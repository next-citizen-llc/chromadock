import Foundation

enum DockIO {
    static func exportPlist() throws -> [String: Any] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("chromadock-export-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try run("/usr/bin/defaults", ["export", "com.apple.dock", tmp.path])
        let data = try Data(contentsOf: tmp)
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: "ChromaDock", code: 1, userInfo: [NSLocalizedDescriptionKey: "Dock preferences were not a dictionary."])
        }
        return dict
    }

    static func importPlist(_ dict: [String: Any]) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("chromadock-import.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try data.write(to: tmp)
        _ = try run("/usr/bin/defaults", ["import", "com.apple.dock", tmp.path])
        _ = try? run("/usr/bin/killall", ["Dock"])
    }

    static func writeBackup(_ dict: [String: Any]) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let url = Paths.backupsDir.appendingPathComponent("com.apple.dock.\(stamp).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try data.write(to: url)
        try data.write(to: Paths.latestBackup)
        return url
    }

    static func restore(from url: URL) throws {
        _ = try run("/usr/bin/defaults", ["import", "com.apple.dock", url.path])
        _ = try? run("/usr/bin/killall", ["Dock"])
    }

    static func persistentApps(_ dict: [String: Any]) -> [[String: Any]] {
        dict["persistent-apps"] as? [[String: Any]] ?? []
    }

    static func bundleID(of tile: [String: Any]) -> String? {
        let type = tile["tile-type"] as? String ?? "file-tile"
        if type.contains("spacer") { return nil }
        let td = tile["tile-data"] as? [String: Any] ?? [:]
        return td["bundle-identifier"] as? String
    }

    static func isDividerTile(_ tile: [String: Any]) -> Bool {
        guard let b = bundleID(of: tile) else {
            let type = tile["tile-type"] as? String ?? ""
            return type.contains("spacer")
        }
        return b.hasPrefix(Paths.dividerBundlePrefix)
            || b.hasPrefix("com.nextcz.dockdivider.")
    }

    static func fileTile(bundle: String, label: String, path: String) -> [String: Any] {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let url = URL(fileURLWithPath: trimmed, isDirectory: trimmed.hasSuffix(".app"))
        var urlString = url.absoluteString
        if trimmed.hasSuffix(".app"), !urlString.hasSuffix("/") { urlString += "/" }
        var td: [String: Any] = [
            "bundle-identifier": bundle,
            "dock-extra": false,
            "file-label": label,
            "file-type": 41,
            "is-beta": false,
            "file-data": [
                "_CFURLString": urlString,
                "_CFURLStringType": 15
            ]
        ]
        if let book = makeBookmark(path: trimmed) {
            td["book"] = book
        }
        return [
            "GUID": UInt32.random(in: 1...UInt32.max),
            "tile-type": "file-tile",
            "tile-data": td
        ]
    }

    static func makeBookmark(path: String) -> Data? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        // Drain pipes before waitUntilExit. A Dock export is ~100 KB; waiting first
        // deadlocks once stdout fills the ~64 KB pipe buffer.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let message = String(data: errData, encoding: .utf8) ?? "command failed"
            throw NSError(domain: "ChromaDock", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }
}
