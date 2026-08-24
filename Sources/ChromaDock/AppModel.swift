import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var apps: [DockApp] = []
    @Published var status: String = "Scan the Dock to begin."
    @Published var lastBackupURL: URL?
    @Published var isBusy = false
    private var helperKeepAlive: Task<Void, Never>?

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

    func refreshAsync(updateBusy: Bool = true) async {
        if updateBusy { isBusy = true }
        status = "Reading Dock icons…"
        defer { if updateBusy { isBusy = false } }
        let settings = self.settings
        do {
            let packed = try await Task.detached(priority: .userInitiated) {
                let dict = try DockIO.exportPlist()
                let dock = Self.dockRows(from: dict, settings: settings)
                let agents = Self.agentRows(existingBundles: Set(dock.map(\.bundle)), settings: settings)
                return (dock: dock, agents: agents)
            }.value
            let running = Self.runningAppRows(
                existingBundles: Set(packed.dock.map(\.bundle) + packed.agents.map(\.bundle)),
                settings: settings
            )
            let runningBundles = Set(running.map(\.bundle))
            let extras = running + packed.agents.filter { !runningBundles.contains($0.bundle) }
            let rows = packed.dock + extras
            var rasters: [HueSampler.Raster?] = []
            rasters.reserveCapacity(rows.count)
            for (index, row) in rows.enumerated() {
                if index == 0 || (index + 1) % 10 == 0 || index + 1 == rows.count {
                    status = "Reading \(row.label)… (\(index + 1)/\(rows.count))"
                }
                rasters.append(HueSampler.rasterize(path: row.path))
                if (index + 1) % 10 == 0 { await Task.yield() }
            }
            let samples = await Task.detached(priority: .userInitiated) {
                rasters.map { $0.flatMap(HueSampler.analyze) }
            }.value
            var scanned: [DockApp] = []
            scanned.reserveCapacity(rows.count)
            for (row, sample) in zip(rows, samples) {
                scanned.append(DockApp(
                    label: row.label,
                    bundleIdentifier: row.bundle,
                    path: row.path,
                    hue: sample?.hue ?? 0,
                    saturation: sample?.sat ?? 0,
                    value: sample?.val ?? 0,
                    colorful: sample?.colorful ?? false,
                    hex: sample?.hex ?? "#888888",
                    groupID: row.groupID,
                    inDock: row.inDock
                ))
            }
            apps = scanned
            let extraCount = extras.count
            if extraCount == 0 {
                status = "\(scanned.count) Dock apps."
            } else {
                status = "\(scanned.count) apps (\(extraCount) not kept in Dock)."
            }
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

    @discardableResult
    func addGroup(after id: String? = nil) -> String {
        let newID = "group-\(UUID().uuidString.prefix(8))"
        let group = DockGroup(id: newID, title: "New Group", sortByHue: true)
        let ungroupedIndex = settings.groups.firstIndex(where: { $0.id == settings.ungroupedID }) ?? settings.groups.count
        var index = ungroupedIndex
        if let id, let clicked = settings.groups.firstIndex(where: { $0.id == id }) {
            index = min(clicked + 1, ungroupedIndex)
        }
        settings.groups.insert(group, at: max(0, index))
        saveSettings()
        return newID
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
        let next = Self.applyingDeleteGroup(
            deletedGroupID: id,
            ungroupedID: settings.ungroupedID,
            apps: apps,
            assignments: settings.assignments
        )
        apps = next.apps
        settings.assignments = next.assignments
        saveSettings()
    }

    func moveGroup(from: IndexSet, to: Int) {
        settings.groups.move(fromOffsets: from, toOffset: to)
        saveSettings()
    }

    func apply() {
        Task { await applyAsync() }
    }

    @discardableResult
    func applyAsync() async -> Bool {
        isBusy = true
        status = "Applying Dock arrangement…"
        defer { isBusy = false }
        await refreshAsync(updateBusy: false)
        let snapshot = (settings: settings, apps: apps)
        do {
            let outcome = try await Self.applyArrangement(settings: snapshot.settings, apps: snapshot.apps)
            lastBackupURL = outcome.backup
            if outcome.helpersExpected > 0, outcome.helpersRunning < outcome.helpersExpected {
                status = "Dock updated. \(outcome.helpersRunning) of \(outcome.helpersExpected) divider lines running."
            } else {
                status = "Dock updated. Backup saved."
            }
            if snapshot.settings.insertDividers, snapshot.settings.keepDividersRunning {
                startDividerHelpersIfNeeded()
            }
            await refreshAsync()
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    func restore() {
        Task { await restoreAsync() }
    }

    @discardableResult
    func restoreAsync() async -> Bool {
        guard let url = lastBackupURL, FileManager.default.fileExists(atPath: url.path) else {
            status = "No backup to restore."
            return false
        }
        isBusy = true
        status = "Restoring previous Dock…"
        defer { isBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try DockIO.restore(from: url)
            }.value
            DividerManager.stopHelpers()
            let dict = try DockIO.exportPlist()
            let needed = DividerManager.dividerCount(in: DockIO.persistentApps(dict))
            if needed > 0 {
                let urls = try DividerManager.ensureHelpers(count: needed)
                if settings.keepDividersRunning {
                    try await Task.sleep(nanoseconds: 1_600_000_000)
                    _ = await DividerManager.launchHelpers(urls)
                    startDividerHelpersIfNeeded()
                }
            }
            status = "Restored previous Dock."
            await refreshAsync()
            return true
        } catch {
            status = error.localizedDescription
            return false
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

    func startDividerHelpersIfNeeded() {
        helperKeepAlive?.cancel()
        guard settings.insertDividers, settings.keepDividersRunning else { return }
        helperKeepAlive = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self != nil else { break }
                let urls = DividerManager.installedHelperURLs()
                if !urls.isEmpty {
                    _ = await DividerManager.launchHelpers(urls)
                }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stopDividerKeepAlive() {
        helperKeepAlive?.cancel()
        helperKeepAlive = nil
        DividerManager.stopHelpers()
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
        let inDock: Bool
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
            let group = resolvedGroup(bundle: bundle, label: label, settings: settings)
            rows.append(DockRow(label: label, bundle: bundle, path: path, groupID: group, inDock: true))
        }
        return rows
    }

    @MainActor
    private static func runningAppRows(existingBundles: Set<String>, settings: AppSettings) -> [DockRow] {
        var seen = existingBundles
        var extras: [DockRow] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            guard let bundle = app.bundleIdentifier, let url = app.bundleURL else { continue }
            guard !bundle.isEmpty, !seen.contains(bundle) else { continue }
            guard !shouldSkipExtra(bundle: bundle, path: url.path) else { continue }
            seen.insert(bundle)
            let label = app.localizedName ?? bundle
            let group = resolvedGroup(bundle: bundle, label: label, settings: settings)
            extras.append(DockRow(label: label, bundle: bundle, path: url.path, groupID: group, inDock: false))
        }
        return extras
    }

    nonisolated private static func agentRows(existingBundles: Set<String>, settings: AppSettings) -> [DockRow] {
        var seen = existingBundles
        var extras: [DockRow] = []
        for agent in launchAgentApps() {
            guard isUserAppPath(agent.path) else { continue }
            guard !agent.bundle.isEmpty, !seen.contains(agent.bundle) else { continue }
            guard !shouldSkipExtra(bundle: agent.bundle, path: agent.path) else { continue }
            seen.insert(agent.bundle)
            let group = resolvedGroup(bundle: agent.bundle, label: agent.label, settings: settings)
            extras.append(DockRow(label: agent.label, bundle: agent.bundle, path: agent.path, groupID: group, inDock: false))
        }
        return extras
    }

    nonisolated private static func shouldSkipExtra(bundle: String, path: String) -> Bool {
        if bundle == "com.apple.finder" || bundle == "com.apple.dock" { return true }
        if bundle.hasPrefix(Paths.dividerBundlePrefix) || bundle.hasPrefix("com.nextcz.dockdivider.") { return true }
        if path.contains("/Contents/Frameworks/") { return true }
        return false
    }

    nonisolated private static func isUserAppPath(_ path: String) -> Bool {
        path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    nonisolated private static func launchAgentApps() -> [(bundle: String, label: String, path: String)] {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var result: [(bundle: String, label: String, path: String)] = []
        for url in files where url.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = obj as? [String: Any] else { continue }
            var program = dict["Program"] as? String
            if program == nil, let args = dict["ProgramArguments"] as? [String] {
                program = args.first
            }
            guard let program, let appPath = appBundlePath(containing: program) else { continue }
            let info = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
            var bundle = (dict["AssociatedBundleIdentifiers"] as? [String])?.first ?? ""
            var label = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            if let infoData = try? Data(contentsOf: info),
               let infoObj = try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil),
               let infoDict = infoObj as? [String: Any] {
                if bundle.isEmpty {
                    bundle = (infoDict["CFBundleIdentifier"] as? String) ?? ""
                }
                label = (infoDict["CFBundleDisplayName"] as? String)
                    ?? (infoDict["CFBundleName"] as? String)
                    ?? label
            }
            if !bundle.isEmpty {
                result.append((bundle, label, appPath))
            }
        }
        return result
    }

    nonisolated private static func appBundlePath(containing executable: String) -> String? {
        let path = executable
        guard let range = path.range(of: ".app", options: [.caseInsensitive]) else { return nil }
        let appPath = String(path[..<range.upperBound])
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appPath, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return appPath
    }

    nonisolated static func rewriteAssignmentsAfterDelete(
        deletedGroupID: String,
        ungroupedID: String,
        assignments: [String: String]
    ) -> [String: String] {
        var next = assignments
        for (bundle, groupID) in assignments where groupID == deletedGroupID {
            next[bundle] = ungroupedID
        }
        return next
    }

    nonisolated static func applyingDeleteGroup(
        deletedGroupID: String,
        ungroupedID: String,
        apps: [DockApp],
        assignments: [String: String]
    ) -> (apps: [DockApp], assignments: [String: String]) {
        let nextAssign = rewriteAssignmentsAfterDelete(
            deletedGroupID: deletedGroupID,
            ungroupedID: ungroupedID,
            assignments: assignments
        )
        var nextApps = apps
        for i in nextApps.indices where nextApps[i].groupID == deletedGroupID {
            nextApps[i].groupID = ungroupedID
        }
        return (nextApps, nextAssign)
    }

    nonisolated static func resolvedGroup(bundle: String, label: String, settings: AppSettings) -> String {
        let raw = settings.assignments[bundle] ?? Heuristic.suggestedGroup(bundle: bundle, label: label)
        if settings.groups.contains(where: { $0.id == raw }) { return raw }
        return settings.ungroupedID
    }

    nonisolated static func willEmitTile(_ app: DockApp, settings: AppSettings, dockedBundles: Set<String>) -> Bool {
        if dockedBundles.contains(app.bundleIdentifier) { return true }
        return settings.assignments[app.bundleIdentifier] != nil && !app.path.isEmpty
    }

    enum DockApplyError: LocalizedError, Equatable {
        case emptyScan
        case noAppTiles

        var errorDescription: String? {
            switch self {
            case .emptyScan:
                return "Scan produced no Dock apps; apply aborted to avoid wiping the Dock."
            case .noAppTiles:
                return "Arrangement produced no app tiles; apply aborted."
            }
        }
    }

    nonisolated static func buildPersistentApps(
        settings: AppSettings,
        apps: [DockApp],
        current: [[String: Any]],
        helperURLs: [URL]
    ) throws -> [[String: Any]] {
        guard apps.contains(where: { $0.inDock }) else {
            throw DockApplyError.emptyScan
        }
        var byBundle: [String: [String: Any]] = [:]
        var spacersAfter: [String: [[String: Any]]] = [:]
        var lastBundle: String?
        for tile in current {
            if DockIO.isNativeSpacer(tile) {
                if let lastBundle {
                    spacersAfter[lastBundle, default: []].append(tile)
                }
                continue
            }
            if DockIO.isDividerTile(tile) { continue }
            if let b = DockIO.bundleID(of: tile) {
                byBundle[b] = tile
                lastBundle = b
            }
        }

        let dockedBundles = Set(byBundle.keys)
        var newApps: [[String: Any]] = []
        var dividerIndex = 0
        var first = true
        for group in settings.groups {
            var members = apps.filter { $0.groupID == group.id && willEmitTile($0, settings: settings, dockedBundles: dockedBundles) }
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
                } else {
                    newApps.append(DockIO.fileTile(
                        bundle: app.bundleIdentifier,
                        label: app.label,
                        path: app.path
                    ))
                }
                if let spacers = spacersAfter[app.bundleIdentifier] {
                    newApps.append(contentsOf: spacers)
                }
            }
        }

        var emitted = Set(newApps.compactMap { tile -> String? in
            if DockIO.isDividerTile(tile) || DockIO.isNativeSpacer(tile) { return nil }
            return DockIO.bundleID(of: tile)
        })
        for tile in current {
            if DockIO.isDividerTile(tile) || DockIO.isNativeSpacer(tile) { continue }
            guard let bundle = DockIO.bundleID(of: tile), !emitted.contains(bundle) else { continue }
            newApps.append(tile)
            emitted.insert(bundle)
            if let spacers = spacersAfter[bundle] {
                newApps.append(contentsOf: spacers)
            }
        }

        let realTiles = newApps.filter { !DockIO.isDividerTile($0) }
        guard !realTiles.isEmpty else {
            throw DockApplyError.noAppTiles
        }
        return newApps
    }

    struct DockApplyOutcome {
        let backup: URL
        let helpersExpected: Int
        let helpersRunning: Int
    }

    nonisolated static func applyArrangement(settings: AppSettings, apps: [DockApp]) async throws -> DockApplyOutcome {
        let dict = try DockIO.exportPlist()
        let backup = try DockIO.writeBackup(dict)
        let current = DockIO.persistentApps(dict)
        var helperURLs: [URL] = []
        if settings.insertDividers {
            let dockedBundles = Set(current.compactMap { DockIO.isDividerTile($0) ? nil : DockIO.bundleID(of: $0) })
            let gaps = max(0, settings.groups.filter { group in
                apps.contains { $0.groupID == group.id && willEmitTile($0, settings: settings, dockedBundles: dockedBundles) }
            }.count - 1)
            helperURLs = try DividerManager.ensureHelpers(count: max(gaps, 0))
        }
        let newApps = try buildPersistentApps(
            settings: settings,
            apps: apps,
            current: current,
            helperURLs: helperURLs
        )

        var next = dict
        next["persistent-apps"] = newApps
        DividerManager.stopHelpers()
        try DockIO.importPlist(next)
        var running = 0
        if settings.insertDividers && settings.keepDividersRunning && !helperURLs.isEmpty {
            try await Task.sleep(nanoseconds: 1_600_000_000)
            let helpers = helperURLs
            running = await DividerManager.launchHelpers(helpers)
        }
        let expected = (settings.insertDividers && settings.keepDividersRunning) ? helperURLs.count : 0
        return DockApplyOutcome(backup: backup, helpersExpected: expected, helpersRunning: running)
    }
}
