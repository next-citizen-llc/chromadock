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
        isBusy = true
        status = "Reading Dock icons…"
        let settings = self.settings
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let scanned = try Self.scanDock(settings: settings)
                DispatchQueue.main.async {
                    self.apps = scanned
                    self.status = "\(scanned.count) Dock apps."
                    self.isBusy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = error.localizedDescription
                    self.isBusy = false
                }
            }
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
        isBusy = true
        status = "Applying Dock arrangement…"
        let snapshot = (settings: settings, apps: apps)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let backup = try Self.applyArrangement(settings: snapshot.settings, apps: snapshot.apps)
                DispatchQueue.main.async {
                    self.lastBackupURL = backup
                    self.status = "Dock updated. Backup saved."
                    self.isBusy = false
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }

    func restore() {
        guard let url = lastBackupURL, FileManager.default.fileExists(atPath: url.path) else {
            status = "No backup to restore."
            return
        }
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try DockIO.restore(from: url)
                DividerManager.stopHelpers()
                DispatchQueue.main.async {
                    self.status = "Restored previous Dock."
                    self.isBusy = false
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = error.localizedDescription
                    self.isBusy = false
                }
            }
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

    nonisolated private static func scanDock(settings: AppSettings) throws -> [DockApp] {
        let dict = try DockIO.exportPlist()
        var result: [DockApp] = []
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
            let sample = HueSampler.sample(path: path)
            let group = settings.assignments[bundle]
                ?? Heuristic.suggestedGroup(bundle: bundle, label: label)
            result.append(DockApp(
                label: label,
                bundleIdentifier: bundle,
                path: path,
                hue: sample?.hue ?? 0,
                saturation: sample?.sat ?? 0,
                value: sample?.val ?? 0,
                colorful: sample?.colorful ?? false,
                hex: sample?.hex ?? "#888888",
                groupID: group
            ))
        }
        return result
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
