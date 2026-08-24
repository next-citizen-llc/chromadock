import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var apps: [DockApp] = []
    @Published var status: String = "Scan the Dock to begin."
    @Published var lastBackupURL: URL?
    @Published var isBusy = false

    init() {
        self.settings = Self.loadSettings()
        if let latest = try? Data(contentsOf: Paths.latestBackup), !latest.isEmpty {
            lastBackupURL = Paths.latestBackup
        }
    }

    var grouped: [(DockGroup, [DockApp])] {
        settings.groups.map { group in
            let members = apps.filter { $0.groupID == group.id }
            let sorted = (settings.sortByHue && group.sortByHue) ? HueSampler.hueSorted(members) : members
            return (group, sorted)
        }.filter { !$0.1.isEmpty || $0.0.id == settings.ungroupedID }
    }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isBusy = true
        status = "Reading Dock icons…"
        defer { isBusy = false }
        let settings = self.settings
        do {
            let rows = try await Task.detached(priority: .userInitiated) {
                let dict = try DockIO.exportPlist()
                return Self.dockRows(from: dict, settings: settings)
            }.value
            var scanned: [DockApp] = []
            scanned.reserveCapacity(rows.count)
            for (index, row) in rows.enumerated() {
                status = "Reading \(row.label)… (\(index + 1)/\(rows.count))"
                await Task.yield()
                let sample = HueSampler.rasterize(path: row.path).flatMap(HueSampler.analyze)
                scanned.append(DockApp(
                    label: row.label,
                    bundleIdentifier: row.bundle,
                    path: row.path,
                    hue: sample?.hue ?? 0,
                    saturation: sample?.sat ?? 0,
                    value: sample?.val ?? 0,
                    colorful: sample?.colorful ?? false,
                    hex: sample?.hex ?? "#888888",
                    groupID: row.groupID
                ))
            }
            apps = scanned
            status = "\(scanned.count) Dock apps."
        } catch {
            status = error.localizedDescription
        }
    }

    func assign(_ app: DockApp, to groupID: String) {
        settings.assignments[app.bundleIdentifier] = groupID
        if let idx = apps.firstIndex(of: app) {
            apps[idx].groupID = groupID
        }
        saveSettings()
    }

    func addGroup() {
        let id = "group-\(UUID().uuidString.prefix(8))"
        settings.groups.insert(DockGroup(id: id, title: "New Group", sortByHue: true), at: max(0, settings.groups.count - 1))
        saveSettings()
    }

    func renameGroup(_ id: String, title: String) {
        if let i = settings.groups.firstIndex(where: { $0.id == id }) {
            settings.groups[i].title = title
            saveSettings()
        }
    }

    func deleteGroup(_ id: String) {
        guard id != settings.ungroupedID else { return }
        settings.groups.removeAll { $0.id == id }
        for i in apps.indices where apps[i].groupID == id {
            apps[i].groupID = settings.ungroupedID
            settings.assignments[apps[i].bundleIdentifier] = settings.ungroupedID
        }
        saveSettings()
    }

    func moveGroup(from: IndexSet, to: Int) {
        settings.groups.move(fromOffsets: from, toOffset: to)
        saveSettings()
    }

    func apply() {
        Task { await applyAsync() }
    }

    func applyAsync() async {
        isBusy = true
        status = "Applying Dock arrangement…"
        defer { isBusy = false }
        let snapshot = (settings: settings, apps: apps)
        do {
            let backup = try await Task.detached(priority: .userInitiated) {
                try Self.applyArrangement(settings: snapshot.settings, apps: snapshot.apps)
            }.value
            lastBackupURL = backup
            status = "Dock updated. Backup saved."
            await refreshAsync()
        } catch {
            status = error.localizedDescription
        }
    }

    func restore() {
        Task { await restoreAsync() }
    }

    func restoreAsync() async {
        guard let url = lastBackupURL, FileManager.default.fileExists(atPath: url.path) else {
            status = "No backup to restore."
            return
        }
        isBusy = true
        status = "Restoring previous Dock…"
        defer { isBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try DockIO.restore(from: url)
                DividerManager.stopHelpers()
            }.value
            status = "Restored previous Dock."
            await refreshAsync()
        } catch {
            status = error.localizedDescription
        }
    }

    func toggleLoginItem(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if on {
                    try SMAppService.mainApp.register()
                    status = "ChromaDock will open at login and keep divider lines drawn."
                } else {
                    try SMAppService.mainApp.unregister()
                    status = "Login item removed."
                }
            } catch {
                status = error.localizedDescription
            }
        } else {
            status = "Open at login requires macOS 13 or later."
        }
    }

    func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: Paths.settingsURL, options: .atomic)
        } catch {
            status = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private static func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: Paths.settingsURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    private struct DockRow: Sendable {
        let label: String
        let bundle: String
        let path: String
        let groupID: String
    }

    nonisolated private static func dockRows(from dict: [String: Any], settings: AppSettings) -> [DockRow] {
        var rows: [DockRow] = []
        for tile in DockIO.persistentApps(dict) {
            if DockIO.isDividerTile(tile) { continue }
            let td = tile["tile-data"] as? [String: Any] ?? [:]
            guard let bundle = td["bundle-identifier"] as? String else { continue }
            let label = (td["file-label"] as? String) ?? (td["label"] as? String) ?? bundle
            let fd = td["file-data"] as? [String: Any] ?? [:]
            var path = fd["_CFURLString"] as? String ?? ""
            if path.hasPrefix("file://") {
                path = URL(string: path)?.path ?? path
            }
            let group = settings.assignments[bundle]
                ?? Heuristic.suggestedGroup(bundle: bundle, label: label)
            rows.append(DockRow(label: label, bundle: bundle, path: path, groupID: group))
        }
        return rows
    }

    nonisolated static func applyArrangement(settings: AppSettings, apps: [DockApp]) throws -> URL {
        let dict = try DockIO.exportPlist()
        let backup = try DockIO.writeBackup(dict)
        let current = DockIO.persistentApps(dict)
        var byBundle: [String: [String: Any]] = [:]
        for tile in current {
            if DockIO.isDividerTile(tile) { continue }
            if let b = DockIO.bundleID(of: tile) {
                byBundle[b] = tile
            }
        }

        var newApps: [[String: Any]] = []
        var dividerIndex = 0
        var helperURLs: [URL] = []
        if settings.insertDividers {
            let gaps = max(0, settings.groups.filter { group in
                apps.contains(where: { $0.groupID == group.id })
            }.count - 1)
            helperURLs = try DividerManager.ensureHelpers(count: max(gaps, 0))
        }

        var first = true
        for group in settings.groups {
            var members = apps.filter { $0.groupID == group.id }
            if members.isEmpty { continue }
            if settings.sortByHue && group.sortByHue {
                members = HueSampler.hueSorted(members)
            }
            if !first && settings.insertDividers {
                dividerIndex += 1
                let helper = helperURLs[min(dividerIndex - 1, max(helperURLs.count - 1, 0))]
                newApps.append(DividerManager.dividerTile(index: dividerIndex, appURL: helper))
            }
            first = false
            for app in members {
                if let tile = byBundle[app.bundleIdentifier] {
                    newApps.append(tile)
                }
            }
        }

        var next = dict
        next["persistent-apps"] = newApps
        try DockIO.importPlist(next)
        if settings.insertDividers && settings.keepDividersRunning {
            Thread.sleep(forTimeInterval: 1.6)
            DispatchQueue.main.async {
                DividerManager.launchHelpers(helperURLs)
            }
        } else {
            DividerManager.stopHelpers()
        }
        return backup
    }
}
