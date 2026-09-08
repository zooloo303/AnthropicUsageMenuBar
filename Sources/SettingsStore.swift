import Foundation

final class SettingsStore: ObservableObject {
    @Published var anthropicAdminKey: String {
        didSet { KeychainHelper.save(key: "anthropic.admin.key", value: anthropicAdminKey) }
    }
    @Published var anthropicMonthlyLimitUSD: Double {
        didSet { UserDefaults.standard.set(anthropicMonthlyLimitUSD, forKey: "anthropic.monthly.limit") }
    }
    @Published var openAIKey: String {
        didSet { KeychainHelper.save(key: "openai.key", value: openAIKey) }
    }
    @Published var openAIMonthlyLimitUSD: Double {
        didSet { UserDefaults.standard.set(openAIMonthlyLimitUSD, forKey: "openai.monthly.limit") }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refresh.interval") }
    }
    @Published var showOpenAI: Bool {
        didSet { UserDefaults.standard.set(showOpenAI, forKey: "show.openai") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.anthropicAdminKey = KeychainHelper.load(key: "anthropic.admin.key") ?? ""
        self.openAIKey = KeychainHelper.load(key: "openai.key") ?? ""
        self.anthropicMonthlyLimitUSD = defaults.object(forKey: "anthropic.monthly.limit") as? Double ?? 100.0
        self.openAIMonthlyLimitUSD = defaults.object(forKey: "openai.monthly.limit") as? Double ?? 100.0
        self.refreshIntervalMinutes = defaults.object(forKey: "refresh.interval") as? Int ?? 60
        self.showOpenAI = defaults.object(forKey: "show.openai") as? Bool ?? true
    }
}
