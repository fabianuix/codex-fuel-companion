import Foundation
import Combine

final class SimulatedCodex: @unchecked Sendable {
    private let lock = NSLock()
    var account = "test-account"
    var spent = false
    var loseFirstResponse = false
    var outcome = ResetOutcome.reset
    private(set) var keys: [String] = []
    private(set) var fetchCount = 0
    func fetch() throws -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        fetchCount += 1
        let object: [String: Any] = [
            "accountId": account,
            "rateLimits": ["limitId": "codex", "primary": ["usedPercent": spent ? 0 : 100, "windowDurationMins": 10080], "credits": ["hasCredits": true, "unlimited": false, "balance": "100"]],
            "rateLimitResetCredits": ["availableCount": spent ? 0 : 1]
        ]
        return Snapshot(limits: try JSONDecoder().decode(LimitsResponse.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    func reset(_ key: String) throws -> ResetOutcome {
        lock.lock(); defer { lock.unlock() }
        keys.append(key)
        if loseFirstResponse && keys.count == 1 {
            spent = true // Simulate a reset applied on the server but its reply lost.
            throw NSError(domain: "SimulatedOffline", code: 1)
        }
        if keys.count > 1 && spent {
            precondition(Set(keys).count == 1, "A retry must not allocate another request key")
            return .alreadyRedeemed
        }
        if outcome == .reset { spent = true }
        return outcome
    }
    var operations: UsageOperations { UsageOperations(fetch: { try self.fetch() }, reset: { try self.reset($0) }) }
}

private final class ReasoningSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> ReasoningEffort {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count == 1 ? .high : .ultra
    }
}

@main struct StoreTests {
    @MainActor static func settle(_ store: UsageStore) async {
        for _ in 0..<400 {
            if !store.refreshing && !store.isResetting { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        preconditionFailure("State did not settle")
    }
    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        preconditionFailure("Reasoning refresh did not finish")
    }
    @MainActor static func testReasoningRefresh(preferences: UserDefaults) async {
        let backend = SimulatedCodex()
        backend.spent = true
        let releaseReasoning = DispatchSemaphore(value: 0)
        let operations = UsageOperations(fetch: { try backend.fetch() }, reset: { try backend.reset($0) }, fetchReasoning: {
            guard releaseReasoning.wait(timeout: .now() + 2) == .success else {
                throw NSError(domain: "ReasoningTestTimeout", code: 1)
            }
            return .ultra
        })
        let successful = UsageStore(operations: operations, preferences: preferences)
        successful.refresh()
        await settle(successful)
        precondition(successful.menuTitle == "100%" && successful.connectionError == nil,
                     "Usage must finish while reasoning metadata is still pending")
        precondition(successful.reasoningEffort == nil)
        releaseReasoning.signal()
        await waitUntil { successful.reasoningEffort == .ultra }
        precondition(successful.menuTitle == "100%" && !successful.isStale)

        let unavailableOperations = UsageOperations(fetch: { try backend.fetch() }, reset: { try backend.reset($0) }, fetchReasoning: {
            throw NSError(domain: "SimulatedReasoningUnavailable", code: 1)
        })
        let unavailable = UsageStore(operations: unavailableOperations, preferences: preferences)
        unavailable.refresh()
        await settle(unavailable)
        await waitUntil { !unavailable.reasoningRefreshing }
        precondition(unavailable.reasoningEffort == nil,
                     "Unavailable reasoning must keep the neutral appearance")
        precondition(unavailable.connectionError == nil && !unavailable.isStale && unavailable.menuTitle == "100%",
                     "A reasoning metadata failure must not turn valid usage into a connection error")
        // The open panel can bypass the background cooldown without fetching usage.
        let baselineReads = backend.fetchCount
        let sequence = ReasoningSequence()
        let rapid = UsageStore(operations: UsageOperations(fetch: { try backend.fetch() }, reset: { try backend.reset($0) }, fetchReasoning: { sequence.next() }), preferences: preferences)
        rapid.refreshReasoning(ifOlderThan: 0)
        await waitUntil { rapid.reasoningEffort == .high }
        var updates = 0
        let rapidObservation = rapid.$reasoningEffort.dropFirst().sink { _ in updates += 1 }
        rapid.refreshReasoning() // Still within the five-second background cooldown.
        try? await Task.sleep(for: .milliseconds(40))
        precondition(updates == 0)
        rapid.refreshReasoning(ifOlderThan: 0)
        rapid.refreshReasoning(ifOlderThan: 0) // A pending request cannot overlap.
        await waitUntil { updates == 1 }
        precondition(rapid.reasoningEffort == .ultra, "A changed reasoning setting must appear without waiting for usage refresh")
        precondition(backend.fetchCount == baselineReads, "Fast reasoning refresh must not increase account requests")
        withExtendedLifetime(rapidObservation) {}
        print("PASS: immediate panel reasoning refresh, background cooldown and no overlapping or account requests")
        precondition(backend.keys.isEmpty, "Reasoning refresh must never consume a reset")
        print("PASS: independent usage and reasoning refresh, Ultra detection, and neutral metadata failure without a usage error")
    }
    @MainActor static func main() async throws {
        let suite = "CodexUsageTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        await testReasoningRefresh(preferences: preferences)
        let backend = SimulatedCodex()
        let store = UsageStore(operations: backend.operations, preferences: preferences)
        precondition(store.showReasoning, "Reasoning is visible by default")
        store.showReasoning = false
        precondition(!UsageStore(operations: backend.operations, preferences: preferences).showReasoning, "An explicit off preference must be preserved")
        store.showReasoning = true

        store.refresh()
        await settle(store)
        precondition(store.showReset && store.canReset && store.availableResets == 1)
        precondition(backend.keys.isEmpty, "Refresh must never consume a reset")
        let initialReads = backend.fetchCount
        store.refresh(ifOlderThan: 29)
        await settle(store)
        precondition(backend.fetchCount == initialReads, "Background polling respects its interval")
        store.refresh() // Opening forces a fresh read, even if the prior result is recent.
        store.refresh() // An already-running read is shared, not duplicated.
        await settle(store)
        precondition(backend.fetchCount == initialReads + 1, "Opening refreshes immediately without overlapping reads")
        store.useReset()
        store.useReset() // Second click while busy is ignored.
        await settle(store)
        precondition(backend.keys.count == 1)
        precondition(store.snapshot.limits?.main.windows.first?.remaining == 100)
        precondition(!store.showReset && !store.canReset)
        precondition(store.menuTitle == "100%")
        precondition(store.resetMessage == "Usage reset.")

        let uncertain = SimulatedCodex()
        uncertain.loseFirstResponse = true
        let first = UsageStore(operations: uncertain.operations, preferences: preferences)
        first.refresh(); await settle(first)
        first.useReset(); await settle(first)
        precondition(first.hasPendingReset)
        let restarted = UsageStore(operations: uncertain.operations, preferences: preferences)
        restarted.refresh(); await settle(restarted)
        precondition(restarted.availableResets == 0 && restarted.showReset && restarted.canReset)
        restarted.useReset(); await settle(restarted)
        precondition(uncertain.keys.count == 2 && Set(uncertain.keys).count == 1)
        precondition(!restarted.hasPendingReset && restarted.resetMessage == "Usage reset.")

        for outcome in [ResetOutcome.noCredit, .nothingToReset] {
            let server = SimulatedCodex(); server.outcome = outcome
            let state = UsageStore(operations: server.operations, preferences: preferences)
            state.refresh(); await settle(state)
            state.useReset(); await settle(state)
            precondition(state.resetMessage == outcome.message)
            precondition(!state.hasPendingReset)
        }
        let switched = SimulatedCodex()
        let state = UsageStore(operations: switched.operations, preferences: preferences)
        state.refresh(); await settle(state)
        switched.account = "different-account"
        state.useReset(); await settle(state)
        precondition(switched.keys.isEmpty, "Never reset a different account after a sign-in change")
        precondition(state.resetMessage?.contains("Account changed") == true)
        let offlineOperations = UsageOperations(fetch: { Snapshot(limitsError: "Offline") }, reset: { _ in .noCredit })
        let offline = UsageStore(operations: offlineOperations, preferences: preferences)
        precondition(offline.isStale && offline.snapshot.limits != nil && offline.menuTitle.hasSuffix(" ·"))
        precondition(!offline.canReset)
        let savedBalance = offline.snapshot.limits?.main.credits?.balance
        offline.refresh(); await settle(offline)
        precondition(offline.snapshot.limits?.main.credits?.balance == savedBalance && offline.isStale)
        precondition(offline.tooltip.contains("last known"))
        offline.shortcutEnabled = false
        offline.creditThreshold = 500
        let restoredOptions = UsageStore(operations: offlineOperations, preferences: preferences)
        precondition(!restoredOptions.shortcutEnabled && restoredOptions.creditThreshold == 500)
        restoredOptions.requestNotifications = { completion in completion(false) }
        restoredOptions.setAlerts(lowCredits: true, enabled: true)
        precondition(!restoredOptions.lowCreditAlerts && restoredOptions.optionError != nil)
        restoredOptions.requestNotifications = { completion in completion(true) }
        restoredOptions.setAlerts(lowCredits: false, enabled: true)
        precondition(restoredOptions.resetAlerts)
        let candidate = AppShortcut(keyCode: 16, modifiers: AppShortcut.standard.modifiers, key: "Y")
        restoredOptions.registerShortcut = { _ in false }
        precondition(!restoredOptions.saveShortcut(candidate))
        precondition(restoredOptions.shortcut == .standard, "A conflict must preserve the previous shortcut")
        restoredOptions.registerShortcut = { _ in true }
        precondition(!restoredOptions.saveShortcut(AppShortcut(keyCode: 16, modifiers: 0, key: "Y")))
        precondition(restoredOptions.saveShortcut(candidate))
        let reloaded = UsageStore(operations: offlineOperations, preferences: preferences)
        precondition(reloaded.shortcut == candidate && reloaded.shortcutEnabled)
        preferences.set(false, forKey: "showPercentage")
        precondition(!UsageStore(operations: offlineOperations, preferences: preferences).menuTitle.isEmpty)
        precondition(!reloaded.alwaysShowBuyCredits && !reloaded.alwaysShowResets)
        func visibilityLimits(_ shortUsed: Double, _ weeklyUsed: Double, _ balance: String, resets: Int = 0) -> LimitsResponse {
            LimitsResponse(rateLimits: LimitBucket(limitId: "codex", limitName: nil,
                primary: LimitWindow(usedPercent: shortUsed, windowDurationMins: 300, resetsAt: nil),
                secondary: LimitWindow(usedPercent: weeklyUsed, windowDurationMins: 10080, resetsAt: nil),
                credits: Credits(hasCredits: balance != "0", unlimited: false, balance: balance), planType: "plus"),
                rateLimitsByLimitId: nil, rateLimitResetCredits: ResetCredits(availableCount: resets), accountId: "visibility-test")
        }
        reloaded.snapshot = Snapshot(limits: visibilityLimits(100, 90, "0"))
        precondition(!reloaded.showBuyCredits && !reloaded.showResetRow && !reloaded.showCreditBalance)
        reloaded.snapshot = Snapshot(limits: visibilityLimits(100, 100, "10"))
        precondition(!reloaded.showBuyCredits && reloaded.showCreditBalance)
        reloaded.snapshot = Snapshot(limits: visibilityLimits(100, 100, "0", resets: 1))
        precondition(reloaded.showBuyCredits && reloaded.showResetRow && reloaded.showCreditBalance)
        reloaded.alwaysShowBuyCredits = true
        reloaded.alwaysShowResets = true
        reloaded.snapshot = Snapshot(limits: visibilityLimits(0, 0, "100"))
        precondition(reloaded.showBuyCredits && reloaded.showResetRow && reloaded.showCreditBalance)
        let restoredVisibility = UsageStore(operations: offlineOperations, preferences: preferences)
        precondition(restoredVisibility.alwaysShowBuyCredits && restoredVisibility.alwaysShowResets)
        precondition(reloaded.resetTimeDisplay == .dateTime && !reloaded.panelPinned && !reloaded.presentationMode)
        let deadline = Date(timeIntervalSince1970: 2_000_000_000)
        func countdown(_ seconds: Double) -> String {
            ResetTimeDisplay.countdown.label(for: deadline, now: deadline.addingTimeInterval(-seconds))
        }
        precondition(countdown(8100) == "Back in 2h 15m")
        precondition(countdown(59) == "Back in less than a minute")
        precondition(countdown(60) == "Back in 1m")
        precondition(countdown(61) == "Back in 2m")
        precondition(countdown(3600) == "Back in 1h 0m")
        precondition(countdown(183600) == "Back in 2d 3h")
        precondition(countdown(0) == "Reset due · refresh to update")
        precondition(countdown(-60) == countdown(0))
        precondition(ResetTimeDisplay.dateTime.label(for: deadline, now: deadline.addingTimeInterval(-60)).hasPrefix("Resets "))
        let normalTitle = reloaded.menuTitle
        var privacyChanged = false
        reloaded.onPresentationModeChange = { privacyChanged = $0 }
        reloaded.resetTimeDisplay = .countdown
        reloaded.panelPinned = true
        reloaded.presentationMode = true
        precondition(privacyChanged && reloaded.menuTitle == "Hidden")
        precondition(reloaded.menuNumericValue == nil && reloaded.gaugeRemaining == nil && !reloaded.canReset)
        precondition(reloaded.tooltip == "Codex Fuel · balances hidden")
        precondition(reloaded.snapshot.limits != nil, "Privacy must preserve the underlying live data")
        preferences.set(true, forKey: "panelPinned") // Legacy saved pin must not enable it on launch.
        let savedDisplay = UsageStore(operations: offlineOperations, preferences: preferences)
        precondition(savedDisplay.resetTimeDisplay == .countdown && !savedDisplay.panelPinned && savedDisplay.presentationMode)
        reloaded.presentationMode = false
        precondition(!privacyChanged && reloaded.menuTitle == normalTitle && reloaded.menuNumericValue != nil)
        let displaySuite = "CodexFuelDisplay-" + UUID().uuidString
        let displayPreferences = UserDefaults(suiteName: displaySuite)!
        defer { displayPreferences.removePersistentDomain(forName: displaySuite) }
        let displayStore = UsageStore(operations: offlineOperations, preferences: displayPreferences)
        precondition(displayStore.menuBarDisplay == .percentage && !displayStore.allowanceAlerts)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let menuLimits = LimitsResponse(rateLimits: LimitBucket(limitId: "codex", limitName: nil,
            primary: LimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: now.timeIntervalSince1970 + 3600),
            secondary: LimitWindow(usedPercent: 80, windowDurationMins: 10080, resetsAt: now.timeIntervalSince1970 + 8100),
            credits: nil, planType: "pro"), rateLimitsByLimitId: nil, rateLimitResetCredits: nil, accountId: "test")
        displayStore.snapshot = Snapshot(limits: menuLimits)
        precondition(displayStore.menuTitle == "20%" && displayStore.menuNumericValue == 20)
        displayStore.menuBarDisplay = .remainingTime
        precondition(displayStore.menuTitle(at: now) == "2h 15m" && displayStore.menuNumericValue == nil)
        precondition(displayStore.menuTitle(at: now.addingTimeInterval(8100)) == "Due")
        precondition(MenuBarDisplay.countdown(to: now.addingTimeInterval(30), now: now) == "<1m")
        precondition(MenuBarDisplay.countdown(to: now.addingTimeInterval(183600), now: now) == "2d 3h")
        displayStore.connectionError = "Offline"
        precondition(displayStore.menuTitle(at: now) == "2h 15m ·")
        displayStore.menuBarDisplay = .iconOnly
        precondition(displayStore.menuTitle.isEmpty && displayStore.menuNumericValue == nil)
        displayStore.presentationMode = true
        precondition(displayStore.menuTitle.isEmpty && displayStore.tooltip == "Codex Fuel · balances hidden")
        displayStore.menuBarDisplay = .remainingTime
        precondition(displayStore.menuTitle == "Hidden")
        displayStore.presentationMode = false
        displayStore.connectionError = nil
        displayStore.snapshot = Snapshot(limits: visibilityLimits(0, 0, "100"))
        precondition(displayStore.menuTitle == "—", "Unknown reset times must not be invented")
        displayStore.requestNotifications = { $0(false) }
        displayStore.setAllowanceAlerts(true)
        precondition(!displayStore.allowanceAlerts && displayStore.optionError != nil)
        displayStore.requestNotifications = { $0(true) }
        displayStore.setAllowanceAlerts(true)
        displayStore.allowanceAlertPreset = .custom
        displayStore.setCustomAllowanceThreshold(120)
        precondition(displayStore.customAllowanceThreshold == 99)
        displayStore.setCustomAllowanceThreshold(-1)
        precondition(displayStore.customAllowanceThreshold == 1)
        displayStore.setCustomAllowanceThreshold(17)
        displayStore.savePinnedPosition(PinnedPanelPosition(x: -900, top: 500))
        let displayRestored = UsageStore(operations: offlineOperations, preferences: displayPreferences)
        precondition(displayRestored.menuBarDisplay == .remainingTime && displayRestored.allowanceAlerts)
        precondition(displayRestored.allowanceAlertPreset == .custom && displayRestored.customAllowanceThreshold == 17)
        precondition(displayRestored.pinnedPosition == PinnedPanelPosition(x: -900, top: 500))
        displayRestored.savePinnedPosition(PinnedPanelPosition(x: .infinity, top: 100))
        precondition(displayRestored.pinnedPosition?.x == -900)
        displayRestored.savePinnedPosition(nil)
        precondition(UsageStore(operations: offlineOperations, preferences: displayPreferences).pinnedPosition == nil)
        // Exercise alert delivery through the actual refresh path, with no system banners.
        let alertSuite = "CodexFuelAllowance-" + UUID().uuidString
        let alertPreferences = UserDefaults(suiteName: alertSuite)!
        defer { alertPreferences.removePersistentDomain(forName: alertSuite) }
        let prior = visibilityLimits(70, 70, "0")
        let after = visibilityLimits(80, 91, "0")
        alertPreferences.set(try JSONEncoder().encode(UsageHistory(limits: prior, date: now)), forKey: "usageHistory")
        let alertOperations = UsageOperations(fetch: { Snapshot(limits: after) }, reset: { _ in .nothingToReset })
        let alertStore = UsageStore(operations: alertOperations, preferences: alertPreferences)
        alertStore.allowanceAlerts = true
        var warnings: [String] = []
        alertStore.onAlert = { alert, body in if alert == .lowAllowance { warnings.append(body) } }
        alertStore.refresh(); await settle(alertStore)
        precondition(warnings.count == 1 && warnings[0].contains("25% alert") && warnings[0].contains("10% alert"))
        alertStore.refresh(); await settle(alertStore)
        precondition(warnings.count == 1)
        let restartedAlerts = UsageStore(operations: alertOperations, preferences: alertPreferences)
        restartedAlerts.onAlert = { _, body in warnings.append(body) }
        restartedAlerts.refresh(); await settle(restartedAlerts)
        precondition(warnings.count == 1, "Restart must not duplicate the low-allowance alert")
        alertPreferences.set(try JSONEncoder().encode(UsageHistory(limits: prior, date: now)), forKey: "usageHistory")
        let privateAlerts = UsageStore(operations: alertOperations, preferences: alertPreferences)
        privateAlerts.presentationMode = true
        privateAlerts.onAlert = { _, body in warnings.append(body) }
        privateAlerts.refresh(); await settle(privateAlerts)
        precondition(warnings.count == 1 && privateAlerts.snapshot.limits?.main.limitingWindow?.remaining == 9)
        privateAlerts.presentationMode = false
        privateAlerts.refresh(); await settle(privateAlerts)
        precondition(warnings.count == 1, "Unhiding balances must not replay muted alerts")
        print("PASS: menu modes, countdown deadlines, privacy, persisted position/options, alert permission and bounds, delivery and deduplication")
        print("PASS: countdown boundaries, default date format, saved display options, privacy outputs and restoration")
        print("PASS: visibility defaults, partially exhausted limits, remaining credits, available resets, overrides, and persistence")
        print("PASS: shortcut validation, conflict rollback, persistence, and always-visible menu balance")
        print("PASS: offline balance restoration and failed refresh retention, saved options, notification permission handling")
        print("PASS: reset UI state, double-click prevention, confirmed refresh, uncertain retry after restart, unavailable resets, and account switch")
    }
}
