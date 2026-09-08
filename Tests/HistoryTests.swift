import Foundation

@main struct HistoryTests {
    static func limits(balance: String, used: Double = 100, reset: Double = 1000, count: Int = 0, account: String = "one") -> LimitsResponse {
        LimitsResponse(rateLimits: LimitBucket(limitId: "codex", limitName: nil, primary: LimitWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: reset), secondary: nil, credits: Credits(hasCredits: true, unlimited: false, balance: balance), planType: nil), rateLimitsByLimitId: nil, rateLimitResetCredits: ResetCredits(availableCount: count), accountId: account)
    }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 2000)
        let high = limits(balance: "120")
        let low = limits(balance: "90")
        precondition(UsageAlert.changes(from: nil, to: low, threshold: 100, now: now).isEmpty)
        precondition(UsageAlert.changes(from: high, to: low, threshold: 100, now: now) == [.lowCredits])
        precondition(UsageAlert.changes(from: low, to: limits(balance: "80"), threshold: 100, now: now).isEmpty)
        precondition(UsageAlert.changes(from: low, to: limits(balance: "80", account: "two"), threshold: 100, now: now).isEmpty)
        let refreshed = limits(balance: "120", used: 0, reset: 5000, count: 1)
        precondition(UsageAlert.changes(from: high, to: refreshed, threshold: 100, now: now) == [.weeklyReset, .resetAvailable])
        precondition(UsageAlert.changes(from: refreshed, to: refreshed, threshold: 100, now: now).isEmpty)
        precondition(!UsageAlert.changes(from: limits(balance: "120", reset: 3000), to: refreshed, threshold: 100, now: now).contains(.weeklyReset), "Manual/early resets are not weekly refreshes")
        var history = UsageHistory(limits: high, date: now)
        history.record(limits(balance: "150"), at: now.addingTimeInterval(4000))
        let saved = try JSONEncoder().encode(history)
        let restored = try JSONDecoder().decode(UsageHistory.self, from: saved)
        precondition(restored.limits.main.credits?.balance == "150")
        precondition(restored.date == now.addingTimeInterval(4000))
        history.record(limits(balance: "130", account: "two"), at: now.addingTimeInterval(86430))
        precondition(history.limits.accountId == "two")
        print("PASS: alert crossings, deduplication, allowance refreshes, cached balance persistence, and account changes")
    }
}
