import SwiftUI
import ServiceManagement

struct UsageOperations: Sendable {
    var fetch: @Sendable () throws -> Snapshot
    var reset: @Sendable (String) throws -> ResetOutcome
    var fetchReasoning: @Sendable () throws -> ReasoningEffort? = { nil }
    static let live = UsageOperations(fetch: { try CodexClient.fetch() },
                                      reset: { try CodexClient.consumeReset(idempotencyKey: $0) },
                                      fetchReasoning: { try CodexClient.fetchReasoning() })
}

@MainActor final class UsageStore: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published private(set) var reasoningEffort: ReasoningEffort?
    private var reasoningRefreshing = false
    private var lastReasoningAttempt: Date?
    var reasoningDescription: String {
        reasoningEffort.map { "\($0.title) reasoning · most recently used Codex task" }
            ?? "Reasoning setting unavailable · showing a neutral bar"
    }
    @Published var refreshing = false
    @Published var isResetting = false
    @Published var resetMessage: String?
    @Published var lastUpdated: Date?
    @Published var connectionError: String?
    @Published var loginError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var lowCreditAlerts: Bool { didSet { preferences.set(lowCreditAlerts, forKey: "lowCreditAlerts") } }
    @Published var resetAlerts: Bool { didSet { preferences.set(resetAlerts, forKey: "resetAlerts") } }
    @Published var creditThreshold: Double { didSet { preferences.set(creditThreshold, forKey: "creditThreshold") } }
    @Published var alwaysShowBuyCredits: Bool { didSet { preferences.set(alwaysShowBuyCredits, forKey: "alwaysShowBuyCredits") } }
    @Published var alwaysShowResets: Bool { didSet { preferences.set(alwaysShowResets, forKey: "alwaysShowResets") } }
    @Published var confirmingQuit = false
    @Published var settingsRequest = 0
    @Published var testingNotifications = false
    @Published var notificationTestStatus: String?
    var runNotificationTests: ((Bool) -> Void)?
    @Published var shortcutRecording = false
    @Published private(set) var shortcut: AppShortcut
    var registerShortcut: ((AppShortcut) -> Bool)?
    @Published var shortcutEnabled: Bool { didSet { preferences.set(shortcutEnabled, forKey: "shortcutEnabled") } }
    @Published var optionError: String?
    var onAlert: ((UsageAlert, String) -> Void)?
    var requestNotifications: ((@escaping (Bool) -> Void) -> Void)?
    private var history: UsageHistory?
    @Published private var resetBook: ResetRequestBook
    private var lastRefreshAttempt: Date?
    private let operations: UsageOperations
    private let preferences: UserDefaults
    init(operations: UsageOperations = .live, preferences: UserDefaults = .standard) {
        self.operations = operations
        self.preferences = preferences
        self.alwaysShowBuyCredits = preferences.bool(forKey: "alwaysShowBuyCredits")
        self.alwaysShowResets = preferences.bool(forKey: "alwaysShowResets")
        self.lowCreditAlerts = preferences.bool(forKey: "lowCreditAlerts")
        self.resetAlerts = preferences.bool(forKey: "resetAlerts")
        let savedThreshold = preferences.double(forKey: "creditThreshold")
        self.creditThreshold = savedThreshold > 0 && savedThreshold.isFinite ? savedThreshold : 100
        self.shortcutEnabled = preferences.object(forKey: "shortcutEnabled") as? Bool ?? true
        self.history = preferences.data(forKey: "usageHistory").flatMap { try? JSONDecoder().decode(UsageHistory.self, from: $0) }
        let savedShortcut = preferences.data(forKey: "keyboardShortcut").flatMap { try? JSONDecoder().decode(AppShortcut.self, from: $0) }
        self.shortcut = savedShortcut.flatMap { $0.isValid ? $0 : nil } ?? .standard
        self.resetBook = preferences.data(forKey: "pendingResets").flatMap { try? JSONDecoder().decode(ResetRequestBook.self, from: $0) } ?? ResetRequestBook()
        if let history {
            snapshot = Snapshot(limits: history.limits)
            lastUpdated = history.date
            connectionError = "Checking connection…"
        }
    }
    func saveShortcut(_ candidate: AppShortcut) -> Bool {
        guard candidate.isValid else { optionError = "Include Command or Control in your shortcut."; return false }
        guard registerShortcut?(candidate) == true else { optionError = "That shortcut is already in use. Try another."; return false }
        shortcut = candidate
        shortcutEnabled = true
        preferences.set(try? JSONEncoder().encode(candidate), forKey: "keyboardShortcut")
        optionError = nil
        return true
    }
    var tooltip: String {
        let balance = snapshot.limits.map { "Codex Fuel · " + $0.main.primaryMenuValue } ?? "Codex Fuel · unavailable"
        let offline = isStale ? "\nOffline · last known balance" + (lastUpdated.map { " from " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "") : ""
        let windows = snapshot.limits?.main.windows.map { "\($0.title) · \(Int($0.remaining))% left" }.joined(separator: "\n") ?? ""
        return balance + (windows.isEmpty ? "" : "\n" + windows) + offline
    }
    func setAlerts(lowCredits: Bool, enabled: Bool) {
        optionError = nil
        guard enabled else {
            if lowCredits { lowCreditAlerts = false } else { resetAlerts = false }
            return
        }
        requestNotifications? { [weak self] allowed in
            guard let self else { return }
            if lowCredits { self.lowCreditAlerts = allowed } else { self.resetAlerts = allowed }
            if !allowed { self.optionError = "Allow notifications for Codex Fuel in System Settings → Notifications." }
        }
    }
    var isStale: Bool { connectionError != nil || snapshot.limitsError != nil }
    var gaugeRemaining: Double? { snapshot.limits?.main.limitingWindow?.remaining }
    var availableResets: Int { max(0, snapshot.limits?.rateLimitResetCredits?.availableCount ?? 0) }
    var hasPendingReset: Bool {
        guard let account = snapshot.limits?.accountId else { return false }
        return resetBook.pending(for: account) != nil
    }
    var showBuyCredits: Bool {
        if alwaysShowBuyCredits { return true }
        guard let bucket = snapshot.limits?.main,
              !bucket.windows.isEmpty || bucket.credits != nil else { return false }
        return bucket.windows.allSatisfy { $0.remaining == 0 } && (bucket.credits?.isDepleted ?? true)
    }
    var showCreditBalance: Bool {
        guard let credits = snapshot.limits?.main.credits else { return false }
        return !credits.isDepleted || showBuyCredits
    }
    var showResetRow: Bool { alwaysShowResets || showReset }
    var showReset: Bool { availableResets > 0 || hasPendingReset || isResetting }
    var canReset: Bool {
        !isResetting && !refreshing && !isStale && snapshot.limits?.accountId != nil && (availableResets > 0 || hasPendingReset)
    }
    var menuNumericValue: Double? {
        guard let bucket = snapshot.limits?.main else { return nil }
        return bucket.usesCredits ? bucket.credits?.balance.flatMap(Double.init) : bucket.limitingWindow?.remaining
    }
    var menuTitle: String {
        guard let bucket = snapshot.limits?.main else { return "—" }
        return bucket.primaryMenuValue + (isStale ? " ·" : "")
    }
    private func accept(_ next: Snapshot) {
        guard let limits = next.limits else {
            connectionError = next.limitsError ?? "Couldn’t refresh usage."
            return
        }
        let now = Date()
        let alerts = UsageAlert.changes(from: history?.limits, to: limits, threshold: creditThreshold, now: now)
        if history == nil { history = UsageHistory(limits: limits, date: now) }
        else { history?.record(limits, at: now) }
        if let history, let data = try? JSONEncoder().encode(history) { preferences.set(data, forKey: "usageHistory") }
        snapshot = next
        connectionError = nil
        lastUpdated = now
        for alert in alerts {
            if alert == .lowCredits && lowCreditAlerts {
                onAlert?(alert, "Your balance is below \(Int(creditThreshold)) credits.")
            } else if alert != .lowCredits && resetAlerts && !isResetting {
                onAlert?(alert, alert == .weeklyReset ? "Your weekly Codex allowance is ready to use." : "Open Codex Fuel to use your available reset.")
            }
        }
    }
    private func refreshReasoning() {
        guard !reasoningRefreshing else { return }
        if let lastReasoningAttempt, Date().timeIntervalSince(lastReasoningAttempt) < 5 { return }
        lastReasoningAttempt = Date()
        reasoningRefreshing = true
        let fetch = operations.fetchReasoning
        Task {
            let effort = await Task.detached(priority: .utility) { try? fetch() }.value
            reasoningEffort = effort
            reasoningRefreshing = false
        }
    }
    func refresh(ifOlderThan age: TimeInterval = 0) {
        refreshReasoning()
        guard !refreshing, !isResetting else { return }
        if let lastRefreshAttempt, Date().timeIntervalSince(lastRefreshAttempt) < age { return }
        lastRefreshAttempt = Date()
        refreshing = true
        let operations = operations
        Task {
            do { accept(try await Task.detached(priority: .utility) { try operations.fetch() }.value) }
            catch { connectionError = error.localizedDescription }
            refreshing = false
        }
    }
    /// Called only by the user's button click, never by the refresh timer.
    func useReset() {
        guard canReset, let account = snapshot.limits?.accountId else { return }
        isResetting = true
        resetMessage = nil
        let operations = operations
        Task {
            defer { isResetting = false }
            do {
                let fresh = try await Task.detached(priority: .utility) { try operations.fetch() }.value
                accept(fresh)
                guard let currentAccount = fresh.limits?.accountId else {
                    resetMessage = "Couldn’t check your account. Refresh and try again."
                    return
                }
                guard currentAccount == account else {
                    resetMessage = "Account changed. Review the usage and try again."
                    return
                }
                let key = resetBook.begin(for: account)
                saveResetBook()
                let outcome = try await Task.detached(priority: .userInitiated) { try operations.reset(key) }.value
                resetBook.complete(for: account)
                saveResetBook()
                resetMessage = outcome.message
                // Always use the backend's new limits; never infer a reset percentage.
                accept(try await Task.detached(priority: .utility) { try operations.fetch() }.value)
            } catch {
                resetMessage = hasPendingReset
                    ? "Reset not confirmed. Check reset to safely retry the same request."
                    : "Couldn’t refresh usage. Please try again."
            }
        }
    }
    private func saveResetBook() {
        if let data = try? JSONEncoder().encode(resetBook) { preferences.set(data, forKey: "pendingResets") }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Allow Codex Fuel in System Settings → Login Items." : nil
        } catch { loginError = "Couldn’t change launch at login. Keep the app in Applications and try again." }
    }
}
