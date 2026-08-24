import Foundation

let args = CommandLine.arguments
if args.contains("--help") || args.contains("-h") {
    fputs("""
    ChromaDock — group Dock apps and hue-sort each group.

      (no args)     open the app
      --apply       apply the saved grouping now
      --restore     restore the last Dock backup
      --help        show this help

    """, stdout)
    exit(0)
}

if args.contains("--apply") || args.contains("--restore") {
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let model = AppModel()
        if args.contains("--restore") {
            model.restore()
        } else {
            model.refresh()
        }
        // Give scan a moment when applying.
        if args.contains("--apply") {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            model.apply()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        } else {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        fputs(model.status + "\n", stdout)
        sem.signal()
        exit(0)
    }
    sem.wait()
} else {
    ChromaDockApp.main()
}
