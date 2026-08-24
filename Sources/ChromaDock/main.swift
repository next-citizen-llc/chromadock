import AppKit
import Foundation

let args = CommandLine.arguments
if args.contains("--help") || args.contains("-h") {
    fputs("""
    ChromaDock — group Dock apps and hue-sort each group.

      (no args)     open the app
      --scan        read Dock icons and print the result
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
        if args.contains("--restore") {
            await model.restoreAsync()
        } else if args.contains("--apply") {
            await model.refreshAsync()
            await model.applyAsync()
        } else {
            await model.refreshAsync()
        }
        fputs(model.status + "\n", stdout)
        exit(model.apps.isEmpty && !args.contains("--restore") ? 1 : 0)
    }
    RunLoop.main.run()
} else {
    ChromaDockApp.main()
}
