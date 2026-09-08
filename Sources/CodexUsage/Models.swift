import Foundation
import Carbon

struct LimitWindow: Codable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    var title: String {
        guard let minutes = windowDurationMins else { return "Usage limit" }
        if minutes == 10080 { return "Weekly limit" }
        if minutes == 300 { return "5-hour limit" }
        if minutes >= 1440 { return "\(minutes / 1440)-day limit" }
        return "\(minutes)-minute limit"
    }
    var reset: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}
struct Credits: Codable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
    var isDepleted: Bool {
        guard !unlimited else { return false }
        if let value = balance.flatMap(Double.init), value.isFinite { return value <= 0 }
        return balance == nil && !hasCredits
    }
    var display: String {
        if unlimited { return "Unlimited" }
        guard let balance else { return hasCredits ? "Available" : "No credits" }
        guard let value = Double(balance) else { return balance }
        return floor(value).formatted(.number.precision(.fractionLength(0)))
    }
}
struct LimitBucket: Codable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: LimitWindow?
    let secondary: LimitWindow?
    let credits: Credits?
    let planType: String?
    var weekly: LimitWindow? { windows.first { $0.windowDurationMins == 10080 } }
    var usesCredits: Bool {
        guard let credits, windows.isEmpty || windows.contains(where: { $0.remaining == 0 }) else { return false }
        return credits.unlimited || (credits.hasCredits && (credits.balance.flatMap(Double.init).map { $0 > 0 } ?? true))
    }
    var primaryMenuValue: String {
        if usesCredits, let credits { return credits.unlimited ? "∞ credits" : "\(credits.display) cr" }
        return limitingWindow.map { "\(Int($0.remaining))%" } ?? "—"
    }
    // The service determines entitlement. Never invent or hide windows by plan name.
    var windows: [LimitWindow] {
        [primary, secondary].compactMap { $0 }.sorted {
            ($0.windowDurationMins ?? Int.max) < ($1.windowDurationMins ?? Int.max)
        }
    }
    var limitingWindow: LimitWindow? { windows.min { $0.remaining < $1.remaining } }
}
struct ResetCredits: Codable, Sendable { let availableCount: Int }
struct LimitsResponse: Codable, Sendable {
    let rateLimits: LimitBucket
    let rateLimitsByLimitId: [String: LimitBucket]?
    let rateLimitResetCredits: ResetCredits?
    let accountId: String?
    var main: LimitBucket { rateLimitsByLimitId?["codex"] ?? rateLimits }
    var planName: String? {
        guard let raw = main.planType ?? rateLimits.planType, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro", "prolite", "pro_lite", "pro_standard", "pro_heavy": return "Pro"
        case "team", "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu", "education": return "Edu"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    var otherBuckets: [LimitBucket] { (rateLimitsByLimitId ?? [:]).filter { $0.key != (main.limitId ?? "codex") }.sorted { $0.key < $1.key }.map(\.value) }
}
struct Snapshot: Sendable {
    var limits: LimitsResponse?
    var limitsError: String?
}

enum ResetOutcome: String, Codable, Sendable {
    case reset, alreadyRedeemed, nothingToReset, noCredit
    var message: String {
        switch self {
        case .reset, .alreadyRedeemed: return "Usage reset."
        case .nothingToReset: return "No usage limit is eligible for a reset yet."
        case .noCredit: return "No resets are available now."
        }
    }
}
struct ResetResponse: Codable { let outcome: ResetOutcome }
/// Retry an uncertain request with the same key, even after restarting the app.
struct ResetRequestBook: Codable {
    private var keys: [String: String] = [:]
    func pending(for account: String) -> String? { keys[account] }
    mutating func begin(for account: String) -> String {
        if let existing = keys[account] { return existing }
        let key = UUID().uuidString
        keys[account] = key
        return key
    }
    mutating func complete(for account: String) { keys.removeValue(forKey: account) }
}

struct AppShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String
    static let standard = AppShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey), key: "C")
    var isValid: Bool { keyCode < 128 && modifiers & UInt32(controlKey | cmdKey) != 0 && !key.isEmpty }
    var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")].map { modifiers & UInt32($0.0) != 0 ? $0.1 : "" }.joined() + key
    }
}

/// A task's selected reasoning setting, not a measurement of work or allowance.
enum ReasoningEffort: String, Sendable, CaseIterable {
    case none, minimal, low, medium, high, xhigh, max, ultra
    var title: String {
        switch self {
        case .none: return "None"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra high"
        case .max: return "Max"
        case .ultra: return "Ultra"
        }
    }
}

struct ReasoningMetadataResponse: Decodable {
    struct Metadata: Decodable { let reasoningEffort: String? }
    let data: [Metadata]
    var effort: ReasoningEffort? {
        data.first?.reasoningEffort.flatMap(ReasoningEffort.init(rawValue:))
    }
}
