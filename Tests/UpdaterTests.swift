import AppKit
import Sparkle

@main struct UpdaterTests {
    @MainActor static func main() async {
        let updater = AppUpdater()
        var installs = 0
        updater.presentUpdate(version: "1.02", userInitiated: false) { choice in
            precondition(choice == .install)
            installs += 1
        }
        precondition(updater.showsBadge && !updater.showingDialog)
        updater.checkNow()
        precondition(updater.showingDialog && updater.phase == .available)
        updater.closeDialog()
        precondition(updater.showsBadge && installs == 0)
        updater.installUpdate(); updater.installUpdate()
        precondition(installs == 1 && updater.phase == .downloading && !updater.showingDialog)
        updater.showDownloadInitiated(cancellation: {})
        updater.showDownloadDidReceiveData(ofLength: 50)
        precondition(updater.progress == nil)
        updater.showDownloadDidReceiveExpectedContentLength(100)
        precondition(updater.progress == 0.5)
        updater.showDownloadDidReceiveData(ofLength: 70)
        precondition(updater.progress == 1)
        updater.showDownloadDidStartExtractingUpdate()
        precondition(updater.phase == .extracting && updater.progress == nil)
        updater.showReady(toInstallAndRelaunch: { choice in
            precondition(choice == .install); installs += 1
        })
        precondition(installs == 2 && updater.phase == .installing)
        var acknowledgements = 0
        updater.showUpdaterError(NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])) { acknowledgements += 1 }
        precondition(updater.phase == .failed && !updater.showsBadge && updater.showingDialog)
        updater.closeDialog(); updater.closeDialog()
        precondition(acknowledgements == 1)
        var cancelled = 0
        updater.showUserInitiatedUpdateCheck { cancelled += 1 }
        updater.closeDialog(); updater.closeDialog()
        precondition(cancelled == 1 && updater.phase == .idle)
        updater.showUpdateNotFoundWithError(NSError(domain: "Test", code: 1001, userInfo: [NSLocalizedDescriptionKey: "You're up to date"])) { acknowledgements += 1 }
        precondition(updater.phase == .current && updater.showingDialog)
        updater.closeDialog()
        precondition(acknowledgements == 2)
        updater.dismissUpdateInstallation()
        precondition(!updater.showsBadge)
        let staged = AppUpdater()
        var stageReplies = 0
        staged.showReady(toInstallAndRelaunch: { choice in precondition(choice == .install); stageReplies += 1 })
        precondition(staged.phase == .available && stageReplies == 0)
        staged.installUpdate()
        precondition(stageReplies == 1)
        await testDemo()
        print("PASS: background badge, manual dialog, later, single-click install, real byte progress, restart consent, errors and cancellation")
    }
    @MainActor static func wait(_ updater: AppUpdater, for phase: AppUpdatePhase) async {
        for _ in 0..<300 {
            if updater.phase == phase { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("Demo did not reach \(phase), found \(updater.phase)")
    }
    @MainActor static func testDemo() async {
        let release = AppUpdater(developmentBuild: false, demoDelay: .milliseconds(10))
        release.setTestingUpdates(true)
        precondition(!release.testingUpdates && release.phase == .idle)
        let demo = AppUpdater(developmentBuild: true, demoDelay: .milliseconds(10))
        for scenario in UpdateDemoScenario.allCases {
            demo.demoScenario = scenario
            demo.setTestingUpdates(true)
            precondition(demo.phase == .checking && demo.showingDialog)
            switch scenario {
            case .current: await wait(demo, for: .current)
            case .checkFailure: await wait(demo, for: .failed)
            default:
                await wait(demo, for: .available)
                demo.closeDialog()
                precondition(demo.showsBadge)
                demo.installUpdate()
                await wait(demo, for: scenario == .success ? .completed : .failed)
            }
            precondition(demo.showingDialog)
            demo.setTestingUpdates(false)
            precondition(demo.phase == .idle && !demo.showingDialog && !demo.canCheck)
        }
        demo.demoScenario = .success
        demo.setTestingUpdates(true)
        demo.closeDialog()
        try? await Task.sleep(for: .milliseconds(50))
        precondition(demo.phase == .idle, "Cancelled check must not show an update later")
        demo.runDemo()
        await wait(demo, for: .available)
        demo.installUpdate()
        demo.setTestingUpdates(false)
        try? await Task.sleep(for: .milliseconds(150))
        precondition(demo.phase == .idle && !demo.showingDialog, "Disabled demo must not resume")
        demo.setTestingUpdates(true)
        demo.demoScenario = .current
        demo.runDemo()
        await wait(demo, for: .current)
        demo.setTestingUpdates(false)
        print("PASS: all five demo scenarios, successful completion, cancellation, off-switch cleanup, replay and release-build exclusion")
    }

}
