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
    case lowCredits, lowAllowance, weeklyReset, resetAvailable
    var title: String {
        switch self {
        case .lowCredits: return "Credits running low"
        case .lowAllowance: return "Allowance running low"
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

struct AllowanceWarning: Equatable {
    let windowTitle: String
    let remaining: Int
    let threshold: Int
    var message: String { "\(windowTitle): \(remaining)% remaining (\(threshold)% alert)." }
    static func crossings(from previous: LimitsResponse?, to next: LimitsResponse, thresholds: [Int]) -> [AllowanceWarning] {
        guard let previous, let account = next.accountId, account == previous.accountId else { return [] }
        return next.main.windows.compactMap { after in
            guard let before = previous.main.windows.first(where: { $0.windowDurationMins == after.windowDurationMins }),
                  before.resetsAt == after.resetsAt else { return nil }
            // One message per window, using the lowest crossed threshold if usage jumps.
            guard let threshold = Set(thresholds).sorted().first(where: {
                (1...99).contains($0) && before.remaining > Double($0) && after.remaining <= Double($0)
            }) else { return nil }
            return AllowanceWarning(windowTitle: after.title, remaining: Int(after.remaining), threshold: threshold)
        }
    }
}
