import SwiftUI

struct ChromaDockApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("ChromaDock", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.automatic)
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
