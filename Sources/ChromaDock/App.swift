import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let url = Bundle.main.bundleURL
        if url.path.hasSuffix("ChromaDock.app") {
            DividerManager.installAppLaunchAgent(appURL: url)
        }
        hideMainWindows()
        DispatchQueue.main.async { [weak self] in
            self?.hideMainWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.hideMainWindows()
        }
        NotificationCenter.default.post(name: .chromaDockDidLaunch, object: nil)
    }

    fileprivate func hideMainWindows() {
        for window in NSApp.windows where window.canBecomeMain || window.canBecomeKey {
            if window.isVisible {
                window.orderOut(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        NotificationCenter.default.post(name: .chromaDockReopen, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension Notification.Name {
    static let chromaDockReopen = Notification.Name("llc.nextcitizen.ChromaDock.reopen")
    static let chromaDockDidLaunch = Notification.Name("llc.nextcitizen.ChromaDock.didLaunch")
}

struct ChromaDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("ChromaDock", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 880, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .onAppear {
                    model.startDividerHelpersIfNeeded()
                    model.ensureLoginAgent()
                }
                .onReceive(NotificationCenter.default.publisher(for: .chromaDockDidLaunch)) { _ in
                    model.startDividerHelpersIfNeeded()
                    model.ensureLoginAgent()
                }
        } label: {
            Text("CD")
        }
        .menuBarExtraStyle(.menu)
    }
}
