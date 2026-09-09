import Foundation

public enum Provider: String, CaseIterable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude" : "Codex" }
    public var usageURL: URL {
        URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage")!
    }
}

public struct UsageWindow: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public var fraction: Double { min(1, max(0, usedPercent / 100)) }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Sendable {
    public let windows: [UsageWindow]
    public let plan: String?
    public let fetchedAt: Date

    public var planDisplayName: String? {
        guard let plan, !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Presentation aliases for reported identifiers, not claims about plan entitlements.
        switch plan.lowercased() {
        case "self_serve_business_prolite": return "Business · Pro Lite"
        case "self_serve_business": return "Business"
        default:
            return plan.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    public init(windows: [UsageWindow], plan: String? = nil, fetchedAt: Date = Date()) {
        self.windows = windows
        self.plan = plan
        self.fetchedAt = fetchedAt
    }
}

public enum UsageError: LocalizedError, Sendable {
    case message(String)
    case throttled(Date)

    public var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .throttled(let date): return "Too many requests. Retrying after \(date.formatted(date: .omitted, time: .shortened))."
        }
    }
}

public enum UsageParser {
    public static func claude(_ data: Data, plan: String? = nil) throws -> UsageSnapshot {
        struct Window: Decodable { let utilization: Double; let resets_at: String? }
        struct Response: Decodable {
            let five_hour: Window?
            let seven_day: Window?
            let seven_day_sonnet: Window?
            let seven_day_opus: Window?
            let seven_day_oauth_apps: Window?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let entries: [(String, String, Window?)] = [
            ("five_hour", "5-hour session", response.five_hour),
            ("seven_day", "Weekly · all models", response.seven_day),
            ("seven_day_sonnet", "Weekly · Sonnet", response.seven_day_sonnet),
            ("seven_day_opus", "Weekly · Opus", response.seven_day_opus),
            ("seven_day_oauth_apps", "Weekly · OAuth apps", response.seven_day_oauth_apps)
        ]
        let windows = entries.compactMap { key, title, window -> UsageWindow? in
            guard let window else { return nil }
            return UsageWindow(id: key, title: title, usedPercent: window.utilization,
                               resetsAt: window.resets_at.flatMap(parseDate))
        }
        guard !windows.isEmpty else { throw UsageError.message("Claude returned no subscription limits for this account.") }
        return UsageSnapshot(windows: windows, plan: plan)
    }

    public static func codex(_ data: Data) throws -> UsageSnapshot {
        struct Window: Decodable { let usedPercent: Double; let windowDurationMins: Int?; let resetsAt: Double? }
        struct Limit: Decodable {
            let primary: Window?; let secondary: Window?; let planType: String?; let limitName: String?
        }
        struct Response: Decodable { let rateLimits: Limit?; let rateLimitsByLimitId: [String: Limit]? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        var limits: [(String, Limit)] = []
        if let all = response.rateLimitsByLimitId, !all.isEmpty {
            limits = all.sorted { lhs, rhs in
                if lhs.key == "codex" { return rhs.key != "codex" }
                if rhs.key == "codex" { return false }
                return lhs.key < rhs.key
            }
        } else if let limit = response.rateLimits { limits = [("codex", limit)] }
        let windows = limits.flatMap { key, limit in
            [("primary", limit.primary), ("secondary", limit.secondary)].compactMap { kind, window -> UsageWindow? in
                guard let window else { return nil }
                let label: String
                switch window.windowDurationMins {
                case 300: label = "5-hour session"
                case 10080: label = "Weekly"
                case .some(let minutes) where minutes % 1440 == 0: label = "\(minutes / 1440)-day window"
                case .some(let minutes) where minutes % 60 == 0: label = "\(minutes / 60)-hour window"
                case .some(let minutes): label = "\(minutes)-minute window"
                case .none: label = kind == "primary" ? "Primary limit" : "Secondary limit"
                }
                return UsageWindow(id: "\(key).\(kind)", title: key == "codex" ? label : "\(limit.limitName ?? key) · \(label)",
                                   usedPercent: window.usedPercent, resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)))
            }
        }
        guard !windows.isEmpty else { throw UsageError.message("No Codex subscription limits returned. Sign in to Codex with your ChatGPT account.") }
        return UsageSnapshot(windows: windows, plan: limits.first?.1.planType)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
