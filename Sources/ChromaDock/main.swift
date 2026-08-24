import AppKit
import Foundation

let args = CommandLine.arguments
if args.contains("--help") || args.contains("-h") {
    fputs("""
    ChromaDock — group Dock apps and hue-sort each group.

      (no args)     open the app
      --scan        read Dock icons and print the result
      --filter Q    with --scan, keep apps whose name contains Q
      --apply       apply the saved grouping now
      --restore     restore the last Dock backup
      --help        show this help

    """, stdout)
    exit(0)
}

if args.contains("--apply") || args.contains("--restore") || args.contains("--scan") {
    _ = NSApplication.shared
    Task { @MainActor in
        let model = AppModel()
        var failed = false
        if args.contains("--restore") {
            failed = !(await model.restoreAsync())
        } else if args.contains("--apply") {
            failed = !(await model.applyAsync())
        } else {
            await model.refreshAsync()
            failed = model.apps.isEmpty
        }
        fputs(model.status + "\n", stdout)
        if args.contains("--scan") {
            var listed = model.apps
            if let i = args.firstIndex(of: "--filter"), args.count > i + 1 {
                let q = args[i + 1].lowercased()
                listed = listed.filter { AppNameFilter.containsName($0.label, query: q) }
            }
            for app in listed {
                let dock = app.inDock ? "dock" : "extra"
                let group = model.settings.groups.first(where: { $0.id == app.groupID })?.title ?? app.groupID
                fputs("\(group)\t\(app.label)\t\(app.bundleIdentifier)\t\(dock)\n", stdout)
            }
        }
        exit(failed ? 1 : 0)
    }
    RunLoop.main.run()
} else {
    ChromaDockApp.main()
}
