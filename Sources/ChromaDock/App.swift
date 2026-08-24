import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        bringMainWindowForward()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        bringMainWindowForward()
        if NSApp.windows.contains(where: { $0.canBecomeMain && $0.isVisible }) {
            return true
        }
        NotificationCenter.default.post(name: .chromaDockReopen, object: nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func bringMainWindowForward() {
        let windows = NSApp.windows.filter { $0.canBecomeMain || $0.canBecomeKey }
        if let match = windows.first(where: { $0.isVisible }) ?? windows.first {
            match.makeKeyAndOrderFront(nil)
        }
    }
}

extension Notification.Name {
    static let chromaDockReopen = Notification.Name("llc.nextcitizen.ChromaDock.reopen")
}

struct ChromaDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("ChromaDock", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 880, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("ChromaDock", systemImage: "rectangle.split.3x1") {
            MenuBarView()
                .environmentObject(model)
        }
    }
}
