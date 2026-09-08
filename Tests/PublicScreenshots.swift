import AppKit
import SwiftUI

/// Render the real views with sample data, never the signed-in account.
@main struct PublicScreenshots {
    @MainActor static func settle(_ seconds: Double = 0.6) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("docs/public/assets/screenshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in ["weekly", "settings", "presentation", "update"] {
            let prefs = UserDefaults(suiteName: "fuel-public-preview-\(UUID().uuidString)")!
            let deadline = Date().addingTimeInterval(2 * 86400 + 5 * 3600)
            let limits = LimitsResponse(rateLimits: LimitBucket(limitId: "codex", limitName: nil,
                primary: nil,
                secondary: LimitWindow(usedPercent: 23, windowDurationMins: 10080, resetsAt: deadline.timeIntervalSince1970),
                credits: nil, planType: "pro"),
                rateLimitsByLimitId: nil, rateLimitResetCredits: nil, accountId: "sample")
            let store = UsageStore(operations: UsageOperations(fetch: { Snapshot(limits: limits) }, reset: { _ in .nothingToReset }, fetchReasoning: { .high }), preferences: prefs)
            store.snapshot = Snapshot(limits: limits)
            store.connectionError = nil
            store.refreshReasoning()
            store.resetTimeDisplay = .countdown
            store.allowanceAlerts = true
            store.presentationMode = name == "presentation"
            let updater = AppUpdater(developmentBuild: false)
            let host = NSHostingView(rootView: UsagePanel(store: store, updater: updater)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 24))
                .environment(\.colorScheme, .dark))
            host.appearance = NSAppearance(named: .darkAqua)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 550), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.backgroundColor = .clear
            window.isOpaque = false
            settle()
            if name == "settings" { store.settingsRequest += 1; settle() }
            if name == "update" { updater.presentUpdate(version: "1.05", userInitiated: false, reply: { _ in }); settle() }
            let size = host.fittingSize
            window.setContentSize(size)
            host.frame = NSRect(origin: .zero, size: size)
            settle()
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Render failed") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            print("Rendered \(name) \(size)")
            window.orderOut(nil)
        }
    }
}
