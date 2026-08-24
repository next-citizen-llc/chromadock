import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedGroup: String?
    @State private var renamingGroupID: String?
    @FocusState private var focusedRenameID: String?

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
            VStack(alignment: .leading, spacing: 0) {
                optionsBar
                Divider()
                if let id = selectedGroup, let group = model.settings.groups.first(where: { $0.id == id }) {
                    groupDetail(group)
                } else {
                    ContentUnavailableView(
                        "Select a group",
                        systemImage: "rectangle.split.3x1",
                        description: Text("Scan the Dock, then assign apps to groups. Apply writes the new order.")
                    )
                }
            }
        }
        .navigationTitle("ChromaDock")
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
            if selectedGroup == nil {
                selectedGroup = model.settings.groups.first?.id
            }
        }
        .onChange(of: selectedGroup) { _, new in
            if let renamingGroupID, renamingGroupID != new {
                self.renamingGroupID = nil
            }
        }
        .onChange(of: renamingGroupID) { _, id in
            focusedRenameID = id
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private func groupRow(_ group: DockGroup) -> some View {
        let count = model.apps.filter { $0.groupID == group.id }.count
        HStack {
            if renamingGroupID == group.id {
                TextField("Group name", text: Binding(
                    get: { group.title },
                    set: { model.renameGroup(group.id, title: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($focusedRenameID, equals: group.id)
                .onSubmit { renamingGroupID = nil }
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
        renamingGroupID = newID
    }

    private func beginRename(_ id: String) {
        selectedGroup = id
        renamingGroupID = id
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

    private var optionsBar: some View {
        HStack(spacing: 16) {
            Toggle("Sort each group by hue", isOn: $model.settings.sortByHue)
                .onChange(of: model.settings.sortByHue) { _, _ in model.saveSettings() }
            Toggle("Transparent divider lines", isOn: $model.settings.insertDividers)
                .onChange(of: model.settings.insertDividers) { _, _ in model.saveSettings() }
            Toggle("Keep lines drawn", isOn: $model.settings.keepDividersRunning)
                .onChange(of: model.settings.keepDividersRunning) { _, _ in model.saveSettings() }
            Spacer()
            Toggle("Open at login", isOn: $model.settings.openAtLogin)
                .onChange(of: model.settings.openAtLogin) { _, on in
                    model.saveSettings()
                    model.toggleLoginItem(on)
                }
        }
        .toggleStyle(.checkbox)
        .padding(10)
    }

    @ViewBuilder
    private func groupDetail(_ group: DockGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Group name", text: Binding(
                    get: { group.title },
                    set: { model.renameGroup(group.id, title: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            List {
                ForEach(model.apps.filter { $0.groupID == group.id }) { app in
                    HStack(spacing: 10) {
                        AppIconView(path: app.path)
                            .frame(width: 28, height: 28)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: app.hex))
                            .frame(width: 14, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4), lineWidth: 0.5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.label)
                            Text(app.colorful ? String(format: "hue %.0f°", app.hueDegrees) : "gray")
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
            }
            .listStyle(.inset)
        }
    }
}

struct AppIconView: View {
    let path: String
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open ChromaDock…") { openWindow(id: "main") }
        Button("Scan Dock") { model.refresh() }
            .disabled(model.isBusy)
        Button("Apply arrangement") { model.apply() }
            .disabled(model.apps.isEmpty || model.isBusy)
        Button("Restore last backup") { model.restore() }
            .disabled(model.lastBackupURL == nil || model.isBusy)
        Divider()
        Button("Quit ChromaDock") { NSApp.terminate(nil) }
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
