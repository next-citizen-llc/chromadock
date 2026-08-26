import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedGroup: String?
    @State private var renamingGroupID: String?
    @State private var appQuery = ""
    @State private var renameDraft = ""
    @State private var groupTitleDraft = ""
    @FocusState private var focusedRenameID: String?
    @FocusState private var groupNameFocused: Bool
    @State private var showPaidComingSoon = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedGroup) {
                ForEach(model.settings.groups) { group in
                    groupRow(group)
                        .tag(group.id)
                        .contextMenu {
                            Button("Create") { createGroup(after: group.id) }
                            Button("Rename") { beginRename(group.id) }
                            if group.id != model.settings.ungroupedID {
                                Divider()
                                Button("Delete Group", role: .destructive) {
                                    deleteGroup(group.id)
                                }
                            }
                        }
                }
                .onMove(perform: model.moveGroup)
            }
            .navigationTitle("Groups")
        } detail: {
            appList
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        optionsBar
                        filterBar
                        if appQueryTrimmed.isEmpty, let id = selectedGroup,
                           let group = model.settings.groups.first(where: { $0.id == id }) {
                            groupNameBar(group)
                            if model.settings.previewHueNudge, !displayedApps.isEmpty {
                                chromaticPreview(displayedApps)
                            }
                        }
                        Divider()
                    }
                    .background(.bar)
                }
        }
        .navigationTitle("ChromaDock")
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Scan Dock", action: model.refresh)
                    .disabled(model.isBusy)
            }
            ToolbarItem(placement: .automatic) {
                Button("Apply") { model.apply() }
                    .disabled(model.isBusy || model.apps.isEmpty)
                    .keyboardShortcut("s", modifiers: [.command])
            }
            ToolbarItem(placement: .automatic) {
                Button("Restore") { model.restore() }
                    .disabled(model.isBusy || model.lastBackupURL == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("New Group", action: { createGroup() })
                    .accessibilityLabel("New Group")
                    .accessibilityIdentifier("new-group")
                Spacer(minLength: 12)
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .padding(10)
            .background(.bar)
        }
        .onAppear {
            if model.apps.isEmpty { model.refresh() }
            model.startDividerHelpersIfNeeded()
            if selectedGroup == nil {
                selectedGroup = model.settings.groups.first?.id
            }
            groupTitleDraft = model.settings.groups.first(where: { $0.id == selectedGroup })?.title ?? ""
        }
        .onChange(of: selectedGroup) { old, new in
            if let old, old != new {
                model.renameGroup(old, title: groupTitleDraft)
            }
            if let renamingGroupID, renamingGroupID != new {
                commitSidebarRename()
            }
            groupTitleDraft = model.settings.groups.first(where: { $0.id == new })?.title ?? ""
        }
        .onChange(of: renamingGroupID) { _, id in
            focusedRenameID = id
        }
        .onChange(of: focusedRenameID) { old, new in
            if new == nil, old != nil {
                commitSidebarRename()
            }
        }
        .onChange(of: groupNameFocused) { _, focused in
            if !focused {
                commitGroupTitle()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private func groupRow(_ group: DockGroup) -> some View {
        let count = model.apps.filter { $0.groupID == group.id }.count
        HStack {
            if renamingGroupID == group.id {
                TextField("Group name", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .focused($focusedRenameID, equals: group.id)
                .onSubmit { commitSidebarRename() }
                .onExitCommand { renamingGroupID = nil }
            } else {
                Text(group.title)
            }
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func createGroup(after id: String? = nil) {
        let newID = model.addGroup(after: id)
        selectedGroup = newID
        renameDraft = "New Group"
        groupTitleDraft = "New Group"
        renamingGroupID = newID
    }

    private func beginRename(_ id: String) {
        selectedGroup = id
        renameDraft = model.settings.groups.first(where: { $0.id == id })?.title ?? ""
        renamingGroupID = id
    }

    private func commitSidebarRename() {
        if let id = renamingGroupID {
            model.renameGroup(id, title: renameDraft)
            if id == selectedGroup {
                groupTitleDraft = renameDraft
            }
        }
        renamingGroupID = nil
    }

    private func commitGroupTitle() {
        guard let id = selectedGroup else { return }
        model.renameGroup(id, title: groupTitleDraft)
    }

    private func deleteGroup(_ id: String) {
        if selectedGroup == id {
            selectedGroup = model.settings.ungroupedID
        }
        if renamingGroupID == id {
            renamingGroupID = nil
        }
        model.deleteGroup(id)
    }

    private var appQueryTrimmed: String {
        appQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredApps: [DockApp] {
        model.apps.filter { AppNameFilter.containsName($0.label, query: appQuery) }
    }

    private var optionsBar: some View {
        HStack(spacing: 16) {
            Toggle("Sort each group dark to light", isOn: $model.settings.sortByHue)
                .onChange(of: model.settings.sortByHue) { _, _ in model.saveSettings() }
            Toggle("Hue nudge preview", isOn: $model.settings.previewHueNudge)
                .onChange(of: model.settings.previewHueNudge) { _, _ in model.saveSettings() }
                .help("Slight in-app hue blend toward neighboring icons. Dock tiles are not recolored.")
            Toggle("Dividers", isOn: $model.settings.insertDividers)
                .onChange(of: model.settings.insertDividers) { _, _ in model.saveSettings() }
            separatorsPicker
            Toggle("Keep dividers drawn", isOn: $model.settings.keepDividersRunning)
                .onChange(of: model.settings.keepDividersRunning) { _, on in
                    model.saveSettings()
                    if on {
                        model.startDividerHelpersIfNeeded()
                    } else {
                        model.stopDividerKeepAlive()
                    }
                }
            Spacer()
            Toggle("Open at login", isOn: $model.settings.openAtLogin)
                .onChange(of: model.settings.openAtLogin) { _, on in
                    model.saveSettings()
                    model.toggleLoginItem(on)
                }
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .sheet(isPresented: $showPaidComingSoon) {
            ContactInterestSheet()
        }
    }

    private var separatorsPicker: some View {
        HStack(spacing: 8) {
            Text("Separators")
                .foregroundStyle(.secondary)
            ForEach(DividerStyle.catalog) { style in
                separatorButton(style)
            }
            Button("Create") { showPaidComingSoon = true }
                .buttonStyle(.link)
                .accessibilityLabel("Create separator")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Separators")
    }

    private func separatorButton(_ style: DividerStyle) -> some View {
        let selected = model.settings.dividerStyle == style
        return Button {
            model.settings.dividerStyle = style
            model.dividerStyleDidChange()
        } label: {
            VStack(spacing: 2) {
                Image(nsImage: separatorPreviewImage(style))
                    .interpolation(.high)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1)
                    )
                Text(style.letter)
                    .font(.caption2)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.settings.insertDividers)
        .accessibilityLabel(style.accessibilityName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func separatorPreviewImage(_ style: DividerStyle) -> NSImage {
        let paint = LineStyle.Paint(white: 0.08, alpha: 0.92)
        if let data = try? DividerManager.markPNG(pixelSize: 64, style: style, paint: paint),
           let image = NSImage(data: data) {
            image.isTemplate = false
            return image
        }
        return NSImage(size: NSSize(width: 64, height: 64))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter apps", text: $appQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter apps")
            if !appQuery.isEmpty {
                Button("Clear") { appQuery = "" }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var displayedApps: [DockApp] {
        if !appQueryTrimmed.isEmpty {
            return model.settings.sortByHue ? HueSampler.hueSorted(filteredApps) : filteredApps
        }
        guard let id = selectedGroup else { return [] }
        return model.grouped.first(where: { $0.0.id == id })?.1 ?? []
    }

    private var displayedNudges: [HueSampler.HueNudge] {
        model.settings.previewHueNudge
            ? HueSampler.neighborAligned(displayedApps)
            : displayedApps.map {
                HueSampler.HueNudge(shiftedHue: $0.hue, deltaTurns: 0, hex: $0.hex, applied: false)
            }
    }

    private var appList: some View {
        List {
            ForEach(Array(displayedApps.enumerated()), id: \.element.id) { index, app in
                appRow(app, nudge: displayedNudges[index], showGroup: !appQueryTrimmed.isEmpty)
            }
        }
        .listStyle(.inset)
        .overlay {
            if !appQueryTrimmed.isEmpty, filteredApps.isEmpty {
                ContentUnavailableView(
                    "No apps match",
                    systemImage: "magnifyingglass",
                    description: Text("Nothing named “\(appQueryTrimmed)”.")
                )
            } else if appQueryTrimmed.isEmpty, selectedGroup == nil {
                ContentUnavailableView(
                    "Select a group",
                    systemImage: "rectangle.split.3x1",
                    description: Text("Scan the Dock, then assign apps to groups. Apply writes the new order.")
                )
            }
        }
    }

    private func groupNameBar(_ group: DockGroup) -> some View {
        HStack {
            TextField("Group name", text: $groupTitleDraft)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 280)
            .focused($groupNameFocused)
            .onSubmit { commitGroupTitle() }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func chromaticPreview(_ apps: [DockApp]) -> some View {
        let nudges = HueSampler.neighborAligned(apps)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Chromatic preview · Dock icons unchanged")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        AppIconView(path: app.path, hueShiftTurns: nudges[index].deltaTurns)
                            .frame(width: 32, height: 32)
                            .accessibilityLabel(app.label)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func appRow(_ app: DockApp, nudge: HueSampler.HueNudge, showGroup: Bool) -> some View {
        let groupTitle = model.settings.groups.first(where: { $0.id == app.groupID })?.title
        HStack(spacing: 10) {
            AppIconView(path: app.path, hueShiftTurns: nudge.deltaTurns)
                .frame(width: 28, height: 28)
            HStack(spacing: 3) {
                swatch(app.hex)
                if nudge.applied {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                    swatch(nudge.hex)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.label)
                HStack(spacing: 6) {
                    if showGroup, let groupTitle {
                        Text(groupTitle)
                    }
                    if app.colorful {
                        if nudge.applied {
                            Text(String(format: "hue %.0f° → %.0f°", app.hueDegrees, nudge.shiftedDegrees))
                        } else {
                            Text(String(format: "hue %.0f°", app.hueDegrees))
                        }
                    } else {
                        Text("gray")
                    }
                    if !app.inDock {
                        Text("not in Dock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Group", selection: Binding(
                get: { app.groupID },
                set: { model.assign(app, to: $0) }
            )) {
                ForEach(model.settings.groups) { g in
                    Text(g.title).tag(g.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private func swatch(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: hex))
            .frame(width: 14, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4), lineWidth: 0.5))
    }
}

struct AppIconView: View {
    let path: String
    var hueShiftTurns: Double = 0

    var body: some View {
        Image(nsImage: Self.icon(path: path, hueShiftTurns: hueShiftTurns))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    private static func icon(path: String, hueShiftTurns: Double) -> NSImage {
        let base = NSWorkspace.shared.icon(forFile: path)
        guard abs(hueShiftTurns) > 1e-6,
              let tiff = base.tiffRepresentation,
              let input = CIImage(data: tiff) else { return base }
        let filter = CIFilter.hueAdjust()
        filter.inputImage = input
        filter.angle = Float(hueShiftTurns * 2 * Double.pi)
        guard let output = filter.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else { return base }
        let shifted = NSImage(cgImage: cg, size: base.size)
        shifted.isTemplate = false
        return shifted
    }
}

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open ChromaDock…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
            .onReceive(NotificationCenter.default.publisher(for: .chromaDockReopen)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        Button("Scan Dock") { model.refresh() }
            .disabled(model.isBusy)
        Button("Apply arrangement") { model.apply() }
            .disabled(model.apps.isEmpty || model.isBusy)
        Button("Restore last backup") { model.restore() }
            .disabled(model.lastBackupURL == nil || model.isBusy)
        Divider()
        Button("Restart divider lines") { model.restartDividerHelpers() }
            .disabled(model.isBusy)
        Button("Restart ChromaDock") { model.restartApp() }
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        self.init(
            .sRGB,
            red: Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8) & 0xFF) / 255,
            blue: Double(n & 0xFF) / 255,
            opacity: 1
        )
    }
}
