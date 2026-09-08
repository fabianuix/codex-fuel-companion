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
        var metadataFinished = false
        // Observe completion even when the published result remains nil.
        let observation = unavailable.$reasoningEffort.dropFirst().sink { _ in metadataFinished = true }
        unavailable.refresh()
        await settle(unavailable)
        await waitUntil { metadataFinished }
        precondition(unavailable.reasoningEffort == nil,
                     "Unavailable reasoning must keep the neutral appearance")
        precondition(unavailable.connectionError == nil && !unavailable.isStale && unavailable.menuTitle == "100%",
                     "A reasoning metadata failure must not turn valid usage into a connection error")
        precondition(backend.keys.isEmpty, "Reasoning refresh must never consume a reset")
        withExtendedLifetime(observation) {}
        print("PASS: independent usage and reasoning refresh, Ultra detection, and neutral metadata failure without a usage error")
    }
    @MainActor static func main() async throws {
        let suite = "CodexUsageTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        await testReasoningRefresh(preferences: preferences)
        let backend = SimulatedCodex()
        let store = UsageStore(operations: backend.operations, preferences: preferences)
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
        print("PASS: visibility defaults, partially exhausted limits, remaining credits, available resets, overrides, and persistence")
        print("PASS: shortcut validation, conflict rollback, persistence, and always-visible menu balance")
        print("PASS: offline balance restoration and failed refresh retention, saved options, notification permission handling")
        print("PASS: reset UI state, double-click prevention, confirmed refresh, uncertain retry after restart, unavailable resets, and account switch")
    }
}
