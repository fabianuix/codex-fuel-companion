import AppKit
import SwiftUI
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let updater = AppUpdater()
    private var systemFeatures: SystemFeatures!
    private var item: NSStatusItem!
    private var panel: GlassPanel!
    private var statusContent: StatusContent!
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var reasoningTimer: Timer?
    private var menuClockTimer: Timer?
    private var needleTimer: Timer?
    private var displayedGauge: Double?
    private var gaugeTarget: Double?
    private func updateGauge(_ remaining: Double?) {
        guard remaining != gaugeTarget else { return }
        gaugeTarget = remaining
        needleTimer?.invalidate()
        guard let end = remaining, let start = displayedGauge,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            displayedGauge = remaining
            statusContent.image = GaugeIcon.image(remaining: remaining)
            return
        }
        let began = Date()
        needleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
            guard let self else { timer.invalidate(); return }
            let progress = min(1, Date().timeIntervalSince(began) / 0.4)
            let eased = progress * progress * (3 - 2 * progress)
            let value = start + (end - start) * eased
            self.displayedGauge = value
            self.statusContent.image = GaugeIcon.image(remaining: value)
            if progress >= 1 { timer.invalidate() }
            }
        }
    }
    private func renderStatus() {
        statusContent.update(text: store.menuTitle, value: store.menuNumericValue, hidden: store.presentationMode)
        if store.presentationMode {
            needleTimer?.invalidate()
            displayedGauge = nil
            gaugeTarget = nil
            statusContent.image = PresentationIcon.image()
            item.button?.toolTip = store.tooltip
            return
        }
        let bucket = store.snapshot.limits?.main
        let creditMode = bucket?.windows.isEmpty == true && bucket?.credits != nil
        if creditMode, let credits = bucket?.credits {
            needleTimer?.invalidate()
            gaugeTarget = nil
            displayedGauge = nil
            statusContent.image = CoinsIcon.image()
            let description = "Codex Fuel · \(credits.display) credits available"
            item.button?.toolTip = description
            statusContent.image?.accessibilityDescription = description
        } else {
            let remaining = store.gaugeRemaining
            updateGauge(remaining)
            item.button?.toolTip = remaining.map { "Codex Fuel · \(Int($0))% remaining" } ?? "Codex Fuel · unavailable"
        }
        item.button?.toolTip = store.tooltip
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIdentity.icon
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusContent = StatusContent(item: item)
        statusContent.image = GaugeIcon.image(remaining: nil)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Codex Fuel · percentage remaining"
        }
        panel = GlassPanel(store: store, updater: updater)
        updater.start()
        panel.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.statusContent.setPanelVisible(visible)
            self.reasoningTimer?.invalidate()
            self.reasoningTimer = nil
            guard visible else { return }
            self.store.refreshReasoning(ifOlderThan: 0)
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.panel.window.isVisible else { return }
                    self.store.refreshReasoning(ifOlderThan: 0)
                }
            }
            timer.tolerance = 0.1
            self.reasoningTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        systemFeatures = SystemFeatures()
        systemFeatures.presentationMode = store.presentationMode
        store.onPresentationModeChange = { [weak self] hidden in
            self?.systemFeatures.presentationMode = hidden
            self?.renderStatus()
        }
        renderStatus()
        systemFeatures.toggle = { [weak self] in self?.toggle() }
        store.requestNotifications = { [weak self] completion in self?.systemFeatures.requestNotifications(completion) }
        store.onAlert = { [weak self] alert, body in self?.systemFeatures.notify(alert, body: body) }
        systemFeatures.onTestStatus = { [weak self] active, message in
            self?.store.testingNotifications = active
            self?.store.notificationTestStatus = message
        }
        store.runNotificationTests = { [weak self] enabled in self?.systemFeatures.testNotifications(enabled) }
        store.registerShortcut = { [weak self] shortcut in self?.systemFeatures.setShortcut(true, shortcut: shortcut) ?? false }
        if !systemFeatures.setShortcut(store.shortcutEnabled, shortcut: store.shortcut) {
            store.optionError = "The keyboard shortcut is already in use. Choose another in Settings."
        }
        observation = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.renderStatus()
                if !self.systemFeatures.setShortcut(self.store.shortcutEnabled && !self.store.shortcutRecording, shortcut: self.store.shortcut), self.store.optionError == nil {
                    self.store.optionError = "The keyboard shortcut is already in use. Choose another in Settings."
                }
                if self.panel.window.isVisible { self.panel.resize() }
            }
        }
        store.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.store.refresh(ifOlderThan: self.panel.window.isVisible ? 14 : 29)
            }
        }
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.store.menuBarDisplay == .remainingTime, !self.store.presentationMode else { return }
                self.renderStatus()
            }
        }
        clock.tolerance = 0.1
        menuClockTimer = clock
        RunLoop.main.add(clock, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        if CommandLine.arguments.contains("--test-notifications"),
           Bundle.main.object(forInfoDictionaryKey: "CodexFuelDevelopmentBuild") as? Bool == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.systemFeatures.testNotifications(true) }
        }
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.toggle() } }
    }
    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent, let button = item.button else { toggle(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            panel.close()
            let menu = NSMenu()
            let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(settings)
            if store.pinnedPosition != nil {
                let restore = NSMenuItem(title: "Return panel to menu bar", action: #selector(returnPanelToMenuBar), keyEquivalent: "")
                restore.target = self
                menu.addItem(restore)
            }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit Codex Fuel", action: #selector(quitImmediately), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else { toggle() }
    }
    @objc private func returnPanelToMenuBar() {
        store.savePinnedPosition(nil)
        guard let button = item.button else { return }
        if !panel.window.isVisible { panel.toggle(from: button) }
        else { panel.resize() }
    }
    @objc private func openSettings() {
        guard let button = item.button else { return }
        if !panel.window.isVisible { panel.toggle(from: button) }
        store.settingsRequest += 1
    }
    @objc private func quitImmediately() { NSApplication.shared.terminate(nil) }
    @objc private func woke() { store.refresh() }
    @objc private func toggle() {
        if let button = item.button {
            if !panel.window.isVisible { store.refresh(); updater.checkInBackground() }
            panel.toggle(from: button)
        }
    }
}

@main struct CodexUsageApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check") {
            do {
                let snapshot = try CodexClient.fetch()
                print("Limits: \(snapshot.limits != nil ? "OK" : "FAILED")")
                if let limits = snapshot.limits {
                    print("Main windows: \(limits.main.windows.count); additional buckets: \(limits.otherBuckets.count)")
                    print("Credits available: \(limits.main.credits != nil)")
                }
                exit(snapshot.limits != nil ? 0 : 1)
            } catch { print(error.localizedDescription); exit(1) }
        }
        let app = NSApplication.shared
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { return }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
