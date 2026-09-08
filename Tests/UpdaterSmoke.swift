import AppKit

@main struct UpdaterSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let updater = AppUpdater()
        var outcome: Bool?
        updater.onCheckCompleted = { outcome = $0 }
        updater.start()
        guard updater.available else { print("FAIL: updater did not start"); exit(1) }
        let deadline = Date().addingTimeInterval(25)
        while outcome == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard outcome == true else { print("FAIL: feed check failed or timed out"); exit(1) }
        while !updater.canCheck && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        updater.checkNow()
        while updater.phase == .checking && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard updater.phase == .current, updater.showingDialog else {
            print("FAIL: manual feed check did not produce the in-panel result"); exit(1)
        }
        guard !NSApp.windows.contains(where: \.isVisible) else {
            print("FAIL: update driver opened an external window"); exit(1)
        }
        updater.closeDialog()
        print("PASS: manual public-feed check produces an in-panel result without an external update window")
        print("PASS: embedded Sparkle starts and checks the real public feed without GitHub credentials")
    }
}
