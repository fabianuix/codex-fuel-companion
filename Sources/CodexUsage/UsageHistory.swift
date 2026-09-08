import Foundation

struct UsageHistory: Codable {
    var limits: LimitsResponse
    var date: Date
    init(limits: LimitsResponse, date: Date) {
        self.limits = limits
        self.date = date
    }
    mutating func record(_ next: LimitsResponse, at now: Date) {
        limits = next
        date = now
    }
    static func balance(_ limits: LimitsResponse) -> Double? {
        guard let credits = limits.main.credits, !credits.unlimited,
              let value = credits.balance.flatMap(Double.init), value.isFinite else { return nil }
        return value
    }

}

enum UsageAlert: String {
    case lowCredits, weeklyReset, resetAvailable
    var title: String {
        switch self {
        case .lowCredits: return "Credits running low"
        case .weeklyReset: return "Weekly allowance refreshed"
        case .resetAvailable: return "A usage reset is available"
        }
    }
    static func changes(from previous: LimitsResponse?, to next: LimitsResponse, threshold: Double, now: Date) -> [UsageAlert] {
        guard let previous, let account = next.accountId, account == previous.accountId else { return [] }
        var result: [UsageAlert] = []
        if let before = UsageHistory.balance(previous), let after = UsageHistory.balance(next), before >= threshold, after < threshold { result.append(.lowCredits) }
        if let before = previous.main.weekly, let after = next.main.weekly,
           let oldReset = before.reset, let newReset = after.reset,
           oldReset <= now, newReset > oldReset, after.remaining > before.remaining { result.append(.weeklyReset) }
        if (previous.rateLimitResetCredits?.availableCount ?? 0) == 0,
           (next.rateLimitResetCredits?.availableCount ?? 0) > 0 { result.append(.resetAvailable) }
        return result
    }
}
